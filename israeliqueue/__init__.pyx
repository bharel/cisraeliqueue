from typing import Hashable, TypeVar, Generic
import threading
from time import monotonic
from libc.stdint cimport uintptr_t
from cython.operator cimport dereference as deref
from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from cpython.object cimport PyObject
from cpython.tuple cimport PyTuple_Pack
from cpython.ref cimport Py_INCREF, Py_DECREF

cdef extern from "limits.h":
    cdef const unsigned int UINT_MAX
cdef extern from "float.h":
    cdef const float FLT_MAX


ctypedef struct Node:
    PyObject* group
    PyObject* value
    Node* next

cdef class _IsraeliQueue:
    cdef:
        dict _groups
        Node* _head
        Node* _tail
        unsigned int _size
        public unsigned int maxsize
        unsigned int _unfinished

    def __cinit__(self, unsigned int maxsize = UINT_MAX):
        self._groups = {}
        self._head = NULL
        self._tail = NULL
        self._size = 0
        self._unfinished = 0
        self.maxsize = maxsize

    def __dealloc__(self):
        cdef Node* current = self._head
        cdef Node* next
        while current:
            next = current.next
            PyMem_Free(current)
            current = next
        
    cdef bint _put(self, object group, object value) except 1:
        assert self._size >= self.maxsize

        cdef:
            Node* node = <Node*>PyMem_Malloc(sizeof(Node))
            Node* next_node
            PyObject* _group = <PyObject*> group
            PyObject* _value = <PyObject*> value
            Node* group_tail_node
        
        if not node:
            raise MemoryError("Failed to allocate memory for new node")

        node.group = _group
        Py_INCREF(_group)
        node.value = _value
        Py_INCREF(_value)

        self._size += 1
        self._unfinished += 1
        group_tail_node_addr = <uintptr_t> self._groups.get(group)
        group_tail_node = <Node *> group_tail_node_addr

        # Mark the new node as the tail of the group
        self._groups[group] = <uintptr_t> node

        # Insert node at the end of the current group
        if group_tail_node:
            next_node = group_tail_node.next
            group_tail_node.next = node
            node.next = next_node
            if group_tail_node == self._tail:
                self._tail = node

        # No group, insert node at the end of the queue
        elif self._tail:
            self._tail.next = node
            self._tail = node

        # Empty queue, insert node as the head and tail
        else:
            self._head = self._tail = node

        return 0

    cdef PyObject* _get(self) except NULL:
        cdef:
            Node* node = self._head
            PyObject* result

        assert node
        self._size -= 1
        self._head = node.next
        if not self._head:
            self._tail = NULL
            self._groups.clear()

        # If the next node is not the same group, remove the group
        # This can throw an exception if __eq__ throws
        elif node.next.group != node.group:
            del self._groups[<object> node.group]

        result = PyTuple_Pack(2, <PyObject*> node.group, <PyObject*> node.value)
        return result

    cpdef int qsize(self) noexcept:
        return self._size

    cpdef bint empty(self) noexcept:
        return self._size == 0

    cpdef bint full(self) noexcept:
        return self._size >= self.maxsize

    cdef bint _task_done(self) except 1:
        if self._unfinished > 0:
            self._unfinished -= 1
        else:
            raise ValueError("task_done() called too many times.")

    cpdef int unfinished_tasks(self) noexcept:
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
    def __init__(self, maxsize: int = UINT_MAX):
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

    def put(self, group: _GT, value: _VT, *,
            timeout: float | None = None) -> None:
        cdef:
            float endtime
            float remaining

        if timeout is not None and not (0 < timeout < FLT_MAX):
            raise ValueError("Timeout value must be non-negative float.")

        with self._not_full:
            if timeout:
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

    def get(self, *, timeout: float | None = None) -> tuple[_GT, _VT]:
        cdef:
            float endtime
            float remaining
            PyObject* result
        with self._not_empty:
            if timeout:
                endtime = monotonic() + timeout
                while self.empty():
                    remaining = endtime - monotonic()
                    if remaining <= 0:
                        raise Empty("empty() timed out")
                    self._not_empty.wait(remaining)
            else:
                while self.empty():
                    self._not_empty.wait()

            result = self._get()
            self._not_full.notify()
            r = <object>result
            deref(result)
            return r

    def task_done(self):
        with self._mutex:
            self._task_done()
            if self._unfinished == 0:
                self._all_tasks_done.notify_all()
    
    def join(self, *, timeout: float | None = None) -> None:
        cdef:
            float endtime
            float remaining
        with self._all_tasks_done:
            if timeout:
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
        cdef PyObject* result
        with self._not_empty:
            if self.empty():
                raise Empty
            result = self._get()
            self._not_full.notify()
            r = <object>result
            deref(result)
        return r

    def put_nowait(self, group: _GT, value: _VT) -> None:
        with self._not_full:
            if self.full():
                raise Full
            self._put(group, value)
            self._not_empty.notify()
    

