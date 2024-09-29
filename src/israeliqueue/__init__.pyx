#cython: language_level=3, auto_pickle=False, always_allow_keywords=False
"""
IsraeliQueue: A Group-Based Queue Implementation

This module provides a Cython-based, thread-safe, and optionally asynchronous 
queue that organizes items by groups. The queue ensures that items belonging 
to the same group are kept together, maintaining their insertion order. 
Internally, the queue uses a linked list of nodes to store elements, where 
each node holds a group, a value, and a pointer to the next node.

### How it Works ###
- Node Structure: Each item in the queue is represented by a `Node` that 
  contains a Python object (`group`) representing its group, the item (`value`), 
  and a pointer to the next `Node` in the queue. Items are linked together based 
  on a long chain of the same group with the last item in the group linking to
  the first item of the next group. Group pointers are stored in a dictionary for
  efficient lookup.

- Group Handling: When an item is added, it checks if the group is already in 
  the queue. If the group exists, the item is placed directly after the last item 
  of that group. If the group does not exist, the item is appended to the tail of 
  the queue.

- Memory Management: The queue manually handles memory allocation using 
  Cython’s `PyMem_Malloc` and `PyMem_Free` to allocate and free `Node` structures, 
  ensuring efficient memory usage for the linked list. Each group's reference count 
  is carefully managed with `Py_INCREF` and `Py_DECREF`.

- Queue Operations:
  - put(): Adds an item to the queue, maintaining group order. If the queue 
    is full, the thread or coroutine is blocked until space is available.
  - get(): Removes and returns the next item in the queue. Items are returned 
    in the order they were added, with group-level ordering respected. If the queue 
    is empty, the thread or coroutine is blocked until an item becomes available.
  - task_done(): Marks a task as complete, signaling that the processing of 
    an item is finished.
  - join(): Blocks until all items have been processed by waiting for the 
    `unfinished` task count to reach zero.

- Thread Safety: `IsraeliQueue` uses locks and conditions to manage access 
  between multiple threads. It ensures that `put()` and `get()` operations are 
  safely executed without race conditions. The module supports timeout functionality 
  for both operations to prevent indefinite blocking.

- Async Support: `AsyncIsraeliQueue` provides the same functionality as 
  `IsraeliQueue` but leverages Python’s `asyncio` for non-blocking I/O operations, 
  allowing for asynchronous `put` and `get` operations within an event loop.

### Exceptions:
- `Full`: Raised when attempting to add an item to a full queue.
- `Empty`: Raised when attempting to retrieve an item from an empty queue.
- `Shutdown`: Custom exception reserved for future use in managing shutdown 
  states for the queue.

This module is suitable for scenarios that require both thread-safe and 
asynchronous group-based task management, such as managing multiple consumers 
and producers across threads or within an event loop.
"""
from types import GenericAlias
from typing import Hashable, TypeVar
from collections import deque
import threading
from time import monotonic
import asyncio
from libc.stdint cimport uintptr_t
from cpython.mem cimport PyMem_Malloc, PyMem_Free
from cpython.object cimport PyObject
from cpython.ref cimport Py_INCREF, Py_DECREF
from cpython.tuple cimport PyTuple_Pack, PyTuple_SET_ITEM, _PyTuple_Resize

cdef extern from "limits.h":
    cdef const unsigned int UINT_MAX
cdef extern from "float.h":
    cdef const float FLT_MAX

cdef extern from "Python.h":
    PyObject* PyTuple_New(Py_ssize_t size) except NULL

__all__  = ["IsraeliQueue", "AsyncIsraeliQueue", "Full", "Empty"]

# For debugging
# cdef void _print_node_chain(Node* node):
#     print("START->", end="")
#     while node != NULL:
#         print(f"({<uintptr_t>node}: {<object>node.group}, {<object>node.value})", end="->")
#         node = node.next
#     print("END")

ctypedef struct Node:
    PyObject* group
    PyObject* value
    Node* next

cdef class _IsraeliQueue:
    cdef:
        # Dictionary to store {group: pointer to last node in group}
        dict _groups

        # Linked list pointers
        Node* _head
        Node* _tail

        # Queue size and unfinished tasks
        unsigned int _size
        unsigned int _maxsize
        unsigned int _unfinished
        PyObject* _last_taken_group

    def __init__(self, object maxsize = None, /):
        """Initialize the IsraeliQueue

        Args:
            maxsize: The maximum number of items that can be stored in the queue.
        """
        super().__init__()
        self.maxsize = maxsize
    
    # Ensure that the object is allocated correctly
    def __cinit__(self):
        self._groups = {}

    def __repr__(self):
        clsname = f"{self.__class__.__module__}.{self.__class__.__qualname__}"
        if self._maxsize == UINT_MAX:
            return f"{clsname}()"
        return f"{clsname}(maxsize={self._maxsize})"


    # Ensure that the memory is deallocated correctly
    def __dealloc__(self):
        cdef Node* current = self._head
        cdef Node* next
        while current != NULL:
            next = current.next
            Py_DECREF(<object> current.group)
            Py_DECREF(<object> current.value)
            PyMem_Free(current)
            current = next

    @property
    def maxsize(self) -> int | None:
        return self._maxsize if self._maxsize != UINT_MAX else None

    @maxsize.setter
    def maxsize(self, value: int | None) -> None:
        if value is not None and (value <= 0 or value > UINT_MAX):
            raise ValueError("maxsize must be a positive integer or None")
        self._maxsize = value if value is not None else UINT_MAX
    
    # Put an item into the queue
    # This method is not thread-safe and should be called within a lock
    # It is also not safe to call this method when the queue is full
    # Returns 0 on success
    cdef bint _put(self, object group, object value) except 1:
        assert self._size < self._maxsize, (
            "Only call ._put() when the queue is not .full()")

        cdef:
            Node* node = <Node*>PyMem_Malloc(sizeof(Node))
            Node* original_next
            Node* group_tail_node
        
        if not node:
            raise MemoryError("Failed to allocate memory for new node")

        node[0] = Node(group=<PyObject*>group, value=<PyObject*>value, next=NULL)
        Py_INCREF(group)
        Py_INCREF(value)

        self._size += 1
        self._unfinished += 1
        group_tail_node_ptr = self._groups.get(group)
        # Mark the new node as the tail of the group
        self._groups[group] = <uintptr_t> node

        # Insert node at the end of the current group
        if group_tail_node_ptr is not None:
            group_tail_node = <Node*> (<uintptr_t> group_tail_node_ptr)
            original_next = group_tail_node.next
            group_tail_node.next = node
            node.next = original_next
            if group_tail_node == self._tail:
                self._tail = node

        # No group, insert node at the beginning / end of the queue
        elif self._tail:
            # Same group as the last taken-out node,
            # insert at the beginning.
            if self._last_taken_group != NULL and (
                    <object> self._last_taken_group) == group:
                node.next = self._head
                self._head = node
            # Different group, insert at the end
            else:
                self._tail.next = node
                self._tail = node

        # Empty queue, insert node as the head and tail
        else:
            self._head = self._tail = node

        return 0

    # Remove and return an item from the queue
    # This method is not thread-safe and should be called within a lock
    # It is also not safe to call this method when the queue is empty
    # Returns a tuple containing the group and the value
    # Returns a new reference.
    cdef tuple _get(self):
        cdef:
            Node* node = self._head
            object result

        assert node, "Only call _get() when the queue is not .empty()"
        self._size -= 1
        self._head = node.next

        # Mark the group as the last taken out
        if node.group != self._last_taken_group:
            if self._last_taken_group != NULL:
                Py_DECREF(<object> self._last_taken_group)
            self._last_taken_group = node.group
            Py_INCREF(<object> node.group)

        try:

            if not self._head:
                self._tail = NULL
                self._groups.clear()

            # If the next node is not the same group, remove the group
            # This can throw an exception if __eq__ throws
            elif node.next == NULL or (<object> node.next.group) != (<object> node.group):
                del self._groups[<object> node.group]
            result = PyTuple_Pack(2, node.group, node.value)
            # Result may be NULL if PyTuple_Pack fails
            return result
        finally:
            Py_DECREF(<object> node.group)
            Py_DECREF(<object> node.value)
            PyMem_Free(node)

    cdef tuple _get_group(self):
        cdef:
            Node* node = self._head
            object group = <object> node.group
            Node* last_node
            int current_size = min(self._size, 16)
            int i = 0
            PyObject* items
            tuple result


        items = PyTuple_New(current_size)

        last_node = (
            <Node*> <uintptr_t> self._groups.pop(group))
        
        try:
            while node is not last_node.next:
                if i >= current_size:
                    current_size << 1  # Double the size
                    if current_size < i:  # We overflowed
                        current_size = self._size
                    try:
                        _PyTuple_Resize(&items, current_size)
                    except:
                        # Restore to usable state even though we lost some items
                        self._groups[group] = <uintptr_t> last_node
                        Py_DECREF(<object> items)
                        raise

                PyTuple_SET_ITEM(
                    <object> items, i,
                    <object> node.value)
                Py_DECREF(<object> node.group)
                PyMem_Free(node)
                i += 1
                node = node.next

            # Resize the tuple to the actual size
            _PyTuple_Resize(&items, i)
            if self._tail == last_node:
                self._tail = NULL

            # Remove last group marking. Makes sure that the next group
            # taken out is not a small one - item group. Higher chance
            # that this is the end-user's intention.
            if self._last_taken_group != NULL:
                Py_DECREF(<object> self._last_taken_group)
                self._last_taken_group = NULL

            result = PyTuple_Pack(2, <PyObject*> group, items)
            # Result may be NULL if PyTuple_Pack fails
            return result
        finally:
            self._head = node
            self._size -= i

    cpdef int qsize(self) noexcept:
        """Return the number of items in the queue."""
        return self._size

    cpdef bint empty(self) noexcept:
        """Return whether the queue is empty or not"""
        return self._size == 0

    cpdef bint full(self) noexcept:
        """Return whether the queue is full or not"""
        return self._size >= self._maxsize

    cpdef object groups(self):
        """Returns the set of groups within the queue"""
        return self._groups.keys()

    # Mark a previous task as done
    cdef bint _task_done(self) except 1:
        if self._unfinished > 0:
            self._unfinished -= 1
        else:
            raise ValueError("task_done() called too many times.")

    cpdef int unfinished_tasks(self) noexcept:
        """Returns the number of unfinished tasks"""
        return self._unfinished


class Full(Exception):
    pass

class Empty(Exception):
    pass

class Shutdown(Exception):
    pass

_GT = TypeVar("_GT", bound=Hashable)
_VT = TypeVar("_VT")

cdef class IsraeliQueue(_IsraeliQueue):
    cdef:
        object _mutex
        object _not_empty
        object _not_full
        object _all_tasks_done

    __class_getitem__ = classmethod(GenericAlias)

    def __init__(self, object maxsize = None, /):
        """Initialize the IsraeliQueue

        Args:
            maxsize: The maximum number of items that can be stored in the queue.
        """
        super().__init__(maxsize)
        self._mutex = threading.Lock()

        # Notify not_empty whenever an item is added to the queue; a
        # thread waiting to get is notified then.
        self._not_empty = threading.Condition(self._mutex)

        # Notify not_full whenever an item is removed from the queue;
        # a thread waiting to put is notified then.
        self._not_full = threading.Condition(self._mutex)

        # Notify all_tasks_done whenever the number of unfinished tasks
        # drops to zero; thread waiting to join() is notified to resume
        self._all_tasks_done = threading.Condition(self._mutex)

    def put(self, group: _GT, value: _VT, /, *,
            timeout: float | None = None) -> None:
        """Put an item into the queue.

        If the queue is full, wait until a free slot is available.

        Args:
            group: The group to which the item belongs.
            value: The item to be added to the queue.
            timeout: The maximum time to wait for a free slot. If not specified,
            the method will block indefinitely until a slot is available.
            Setting the timeout to 0 is equivalent to put_nowait().

        
        Raises:
            Full: If the queue is full and the timeout is reached.
        """
        cdef:
            float endtime
            float remaining

        if timeout is not None and not (0 <= timeout < FLT_MAX):
            raise ValueError("Timeout value must be non-negative float.")

        with self._not_full:
            if timeout is not None:
                endtime = monotonic() + timeout
                while self.full():
                    remaining = endtime - monotonic()
                    if remaining <= 0:
                        raise Full("put() timed out")
                    self._not_full.wait(remaining)
            else:
                while self.full():
                    self._not_full.wait()
            self._put(group, value)
            self._not_empty.notify()

    # This method is not thread-safe and should be called within a lock
    # Waits until an item is available in the queue
    # Raises Empty if the timeout is reached

    cdef bint _ensure_not_empty(self, float timeout) except 1:
        if timeout >= 0:
            endtime = monotonic() + timeout
            while self.empty():
                remaining = endtime - monotonic()
                if remaining <= 0:
                    raise Empty("empty() timed out")
                self._not_empty.wait(remaining)
        else:
            while self.empty():
                self._not_empty.wait()

    def get(self, *, timeout: float | None = None) -> tuple[_GT, _VT]:
        """Remove and return an item from the queue.

        If the queue is empty, wait until an item is available.

        Args:
            timeout: The maximum time to wait for an item. If not specified,
            the method will block indefinitely until an item is available.
            Setting the timeout to 0 is equivalent to get_nowait().

        Returns:
            A tuple containing the group and the item removed from the queue.
        
        Raises:
            Empty: If the queue is empty and the timeout is reached.
        """
        cdef tuple result

        if timeout is not None and not (0 <= timeout < FLT_MAX):
            raise ValueError("Timeout value must be non-negative float.")

        with self._not_empty:
            self._ensure_not_empty(timeout if timeout is not None else -1)
            result = self._get()
            self._not_full.notify()
            return result

    def get_group(self, *, timeout: float | None = None
                  ) -> tuple[_GT, tuple[_VT, ...]]:
        """Remove and return all values from the queue with the same group.

        If the queue is empty, wait until an item is available.

        Args:
            timeout: The maximum time to wait for an item. If not specified,
            the method will block indefinitely until an item is available.
            Setting the timeout to 0 is equivalent to get_group_nowait().

        Returns:
            A tuple containing the group and a tuple of values removed from
            the queue.
        
        Raises:
            Empty: If the queue is empty and the timeout is reached.
        """
        cdef tuple result

        if timeout is not None and not (0 <= timeout < FLT_MAX):
            raise ValueError("Timeout value must be non-negative float.")

        with self._not_empty:
            self._ensure_not_empty(timeout if timeout is not None else -1)
            result = self._get_group()
            # Notify all putters
            for _ in result[1]:
                self._not_full.notify()
            return result

    def get_group_nowait(self) -> tuple[_GT, tuple[_VT]]:
        """Remove and return all values from the queue with the same group without blocking.

        Returns:
            A tuple containing the group and a tuple of values removed from
            the queue.
        
        Raises:
            Empty: If the queue is empty.
        """
        cdef tuple result

        with self._not_empty:
            if self.empty():
                raise Empty
            result = self._get_group()
            # Notify all putters
            for _ in result[1]:
                self._not_full.notify()

            return result

    def task_done(self):
        """Indicate that a formerly enqueued task is complete.

        Used by queue consumers. For each `get` used to fetch a task, a
        subsequent call to `task_done` tells the queue that the processing
        on the task is complete.
        """
        with self._mutex:
            self._task_done()
            if self._unfinished == 0:
                self._all_tasks_done.notify_all()
    
    def join(self, *, timeout: float | None = None) -> None:
        """Block until all items in the queue have been processed.

        This method waits until the queue is empty and all tasks are done.

        Args:
            timeout: The maximum time to wait for all tasks to be done. If not
            specified, the method will block indefinitely until all tasks are done.

        Raises:
            TimeoutError: If the timeout is reached before all tasks are done.
        """
        cdef:
            float endtime
            float remaining
        with self._all_tasks_done:
            if timeout is not None:
                endtime = monotonic() + timeout
                while self._unfinished > 0:
                    remaining = endtime - monotonic()
                    if remaining <= 0:
                        raise TimeoutError("join() timed out")
                    self._all_tasks_done.wait(remaining)
            else:
                while self._unfinished > 0:
                    self._all_tasks_done.wait()
    
    def get_nowait(self) -> tuple[_GT, _VT]:
        """Remove and return an item from the queue without blocking.

        Returns:
            A tuple containing the group and the item removed from the queue.
        
        Raises:
            Empty: If the queue is empty.
        """
        cdef tuple result
        with self._not_empty:
            if self.empty():
                raise Empty
            result = self._get()
            self._not_full.notify()
            return result

    def put_nowait(self, group: _GT, value: _VT, /) -> None:
        """Put an item into the queue without blocking.

        Args:
            group: The group to which the item belongs.
            value: The item to be added to the queue.
        
        Raises:
            Full: If the queue is full.
        """
        with self._not_full:
            if self.full():
                raise Full
            self._put(group, value)
            self._not_empty.notify()


cdef class AsyncIsraeliQueue(_IsraeliQueue):
    cdef:
        object _put_waiters
        object _get_waiters
        object _unfinished_waiter

    __class_getitem__ = classmethod(GenericAlias)
    
    def __init__(self, object maxsize = None, /):
        """Initialize the AsyncIsraeliQueue.

        Args:
            maxsize: The maximum number of items that can be stored in the queue.
        """
        super().__init__(maxsize)
        self._put_waiters = deque()
        self._get_waiters = deque()
        self._unfinished_waiter = None

    # Wakeup a single getter
    cdef _wakeup_getter(self):
        while self._get_waiters:
            get_waiter = self._get_waiters.popleft()
            if not get_waiter.done():
                get_waiter.set_result(None)
                break

    # Wakeup a single putter
    cdef _wakeup_putter(self):
        while self._put_waiters:
            put_waiter = self._put_waiters.popleft()
            if not put_waiter.done():
                put_waiter.set_result(None)
                break

    async def put(self, group: Hashable, value: object, /) -> None:
        """Put an item into the queue.

        If the queue is full, wait until a free slot is available.

        If you wish to set a timeout, use `asyncio.wait_for` with this method.

        Args:
            group: The group to which the item belongs.
            value: The item to be added to the queue.
        """
        while self.full():
            put_waiter = asyncio.get_event_loop().create_future()
            self._put_waiters.append(put_waiter)
            await put_waiter

        self._put(group, value)

        # Wakeup a single getter
        self._wakeup_getter()

    def put_nowait(self, group: Hashable, value: object, /) -> None:
        """Put an item into the queue without blocking.

        Args:
            group: The group to which the item belongs.
            value: The item to be added to the queue.

        Raises:
            Full: If the queue is full.
        """
        if self.full():
            raise Full

        self._put(group, value)

        # Wakeup a single getter
        self._wakeup_getter()

    async def get(self) -> tuple[Hashable, object]:
        """Remove and return an item from the queue.

        If the queue is empty, wait until an item is available.

        If you wish to set a timeout, use `asyncio.wait_for` with this method.

        Returns:
            A tuple containing the group and the item removed from the queue.
        """
        while self.empty():
            get_waiter = asyncio.get_event_loop().create_future()
            self._get_waiters.append(get_waiter)
            await get_waiter

        result = self._get()

        # Wakeup a single putter
        self._wakeup_putter()
        
        return result

    def get_nowait(self) -> tuple[Hashable, object]:
        """Remove and return an item from the queue without blocking.

        Returns:
            A tuple containing the group and the item removed from the queue.
        
        Raises:
            Empty: If the queue is empty.
        """
        if self.empty():
            raise Empty

        result = self._get()

        # Wakeup a single putter
        self._wakeup_putter()

        return result

    async def get_group(self) -> tuple[Hashable, tuple[object]]:
        """Remove and return all values from the queue with the same group.

        If the queue is empty, wait until an item is available.

        If you wish to set a timeout, use `asyncio.wait_for` with this method.

        Returns:
            A tuple containing the group and a tuple of values removed from
            the queue.
        """
        while self.empty():
            get_waiter = asyncio.get_event_loop().create_future()
            self._get_waiters.append(get_waiter)
            await get_waiter

        result = self._get_group()

        # Wakeup all putters
        for _ in result[1]:
            self._wakeup_putter()

        return result

    def get_group_nowait(self) -> tuple[Hashable, tuple[object]]:
        """Remove and return all values from the queue with the same group without blocking.

        Returns:
            A tuple containing the group and a tuple of values removed from
            the queue.
        
        Raises:
            Empty: If the queue is empty.
        """
        if self.empty():
            raise Empty

        result = self._get_group()

        # Wakeup all putters
        for _ in result[1]:
            self._wakeup_putter()

        return result

    def task_done(self) -> None:
        """Indicate that a formerly enqueued task is complete.

        Used by queue consumers. For each `get` used to fetch a task, a
        subsequent call to `task_done` tells the queue that the processing
        on the task is complete.
        """
        self._task_done()
        if self._unfinished == 0:
            waiter = self._unfinished_waiter
            if waiter is not None and not waiter.done():
                self._unfinished_waiter.set_result(None)


    async def join(self) -> None:
        """Block until all items in the queue have been processed.

        This method waits until the queue is empty and all tasks are done.

        If you wish to set a timeout, use `asyncio.wait_for` with this method.
        """
        if self._unfinished == 0:
            return

        waiter = self._unfinished_waiter
        if waiter is None or waiter.done():
            waiter = self._unfinished_waiter = (
                asyncio.get_event_loop().create_future())

        await waiter
