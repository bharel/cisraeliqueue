:mod:`israeliqueue` --- IsraeliQueue implementation in C
========================================================

.. module:: israeliqueue
   :synopsis: Main module for the IsraeliQueue package.

**Source code:** :source:`__init__.pyx`

A Cython implementation of a queue system where each item is associated with a "group." The queue processes items in groups, ensuring that items belonging to the same group are dequeued together.

The package contains two classes: :class:`IsraeliQueue` and
:class:`AsyncIsraeliQueue`.

:class:`IsraeliQueue` is a synchronous thread-safe queue. It allows you to
wait on the queue and block the current thread until a task is available.

:class:`AsyncIsraeliQueue` is an asynchronous queue that works with Python's
:mod:`asyncio` framework. It provides non-blocking, asynchronous methods for queue
operations and is suitable for applications requiring high concurrency and
asynchronous task management.

Both classes have an interface similar to Python's built-in :class:`queue.Queue` and :class:`asyncio.Queue` classes.

What is an Israeli Queue?
=========================
An Israeli Queue is a type of priority queue where tasks are grouped together in the same priority. Adding new tasks to the queue will cause them to skip the line and group together. The tasks will then be taken out in-order, group by group.

Why is this useful?
-------------------
IsraeliQueues enjoy many benefits from processing grouped tasks in batches. For example, imagine a bot or an API that requires logging in to a remote repository in order to bring files:

.. code-block:: python

    def login(repo_name: str):
        return Session("repo_name")  # Expensive operation

    def download_file(session: Session, filename: str):
        return Session.download(filename)

    def logout(session: Session):
        session.logout

Now, we have a thread or an asyncio task that adds files to download to the queue:

.. code-block:: python

    from israeliqueue import IsraeliQueue
    queue = IsraeliQueue()
    queue.put("cpython", "build.bat")
    queue.put("black", "pyproject.toml")
    queue.put("black", "bar")  # Same repo as the second item
    queue.put("cpython", "index.html")  # Same repository as the first item

An ordinary queue will cause our bot to login and logout four times, processing each item individually.
The IsraeliQueue groups the repositories together, saving setup costs and allowing to download them all in the same request:

.. code-block:: python

    while True:
        group, items = queue.get_group()
        session = login(group)
        for item in items:
            download_file(session, item)
        logout(session)

If the downloading process accepts multiple files at once, it's even more efficient:

.. code-block:: python

    session.download_files(*items)

Other uses may include batching together AWS queries, batching numpy calculations, and plenty more!

Quickstart
==========
Installation
------------
To install the package, simply ``pip install cisraeliqueue``.

You can use the classes in your project as follows:

.. code-block:: python

    from israeliqueue import IsraeliQueue, AsyncIsraeliQueue

Synchronous Example
-------------------

.. code-block:: python

    from israeliqueue import IsraeliQueue

    # Initialize the queue
    queue = IsraeliQueue(maxsize=10)

    # Add items to the queue
    queue.put('group1', 'task1')
    queue.put('group1', 'task2')
    queue.put('group2', 'task3')

    # Get items from the queue
    group, task = queue.get()
    print(f"Processing {task} from {group}")

    # Get all items from the same group
    group, tasks = queue.get_group()
    print(f"Processing all tasks from {group}: {tasks}")

    # Mark the task as done
    queue.task_done()

    # Wait for all tasks to complete
    queue.join()

Asynchronous Example
--------------------

.. code-block:: python

    import asyncio
    from israeliqueue import AsyncIsraeliQueue

    async def main():
        # Initialize the queue
        queue = AsyncIsraeliQueue(maxsize=10)

        # Add items to the queue
        await queue.put('group1', 'task1')
        await queue.put('group1', 'task2')
        await queue.put('group2', 'task3')

        # Get items from the queue
        group, task = await queue.get()
        print(f"Processing {task} from {group}")

        # Get all items from the same group
        group, tasks = await queue.get_group()
        print(f"Processing all tasks from {group}: {tasks}")

        # Mark the task as done
        queue.task_done()

        # Wait for all tasks to complete
        await queue.join()

    # Run the async example
    asyncio.run(main())

Classes
=======

.. class:: IsraeliQueue[GT, VT](maxsize=None)

    This is the synchronous implementation of the Israeli Queue. It provides
    group-based task processing and supports both blocking and non-blocking
    queue operations. The class is thread-safe and can be used in multithreaded
    environments.

    *GT* is the type of the group key. It must be a
    :class:`~collections.abc.Hashable` object. *VT* is the type of the value
    stored in the queue.

    An :class:`IsraeliQueue` has the following attributes:

    .. attribute:: maxsize

        The maximum number of items that can be placed in the queue. If the
        queue is full, any further attempts to add items will block until space
        becomes available. By default, the queue has no size limit
        (``maxsize=None``).

    An :class:`IsraeliQueue` instance has the following methods:

    .. method:: put(group, value, /, *, [timeout])

        Put a value into the queue. If the queue is full, this method will block
        until space becomes available.

        *group* is any :class:`~collections.abc.Hashable` object that represents
        the group to which the value belongs.
        
        *value* is the task to be added to the queue.

        *timeout* is an optional parameter that specifies the maximum time in
        seconds to wait for space to become available.
        
        If the queue is full and the timeout is reached, a :exc:`~Full` exception is raised.


    .. method:: put_nowait(group, value, /)

        Put a value into the queue without blocking. If the queue is full, a
        :exc:`~Full` exception is raised.

        Equivalent to ``put(group, value, timeout=0)``.

    .. method:: get(*, [timeout])

        Remove and return a ``(group, value)`` tuple from the queue. If the queue is empty, this
        method will block until a value becomes available.

        *timeout* is an optional parameter that specifies the maximum time in
        seconds to wait for a value to become available.
        
        If the queue is empty and the timeout is reached, an :exc:`~Empty` exception is raised.

    .. method:: get_nowait()
            
        Remove and return an value from the queue without blocking. If the queue
        is empty, an :exc:`~Empty` exception is raised.

        Equivalent to ``get(timeout=0)``.

    .. method:: get_group(*, [timeout])

        Remove and return a ``(group, (values, ...))`` tuple from the queue. If the queue is empty, this
        method will block until a value becomes available.

        *timeout* is an optional parameter that specifies the maximum time in
        seconds to wait for a value to become available.
        
        If the queue is empty and the timeout is reached, an :exc:`~Empty` exception is raised.

    .. method:: get_group_nowait()
            
        Remove and return a ``(group, (values, ...))`` tuple from the queue without blocking. If the queue
        is empty, an :exc:`~Empty` exception is raised.

        Equivalent to ``get_group(timeout=0)``.

    .. method:: task_done()

        Indicate that a formerly enqueued task is complete. Used by queue
        consumers. For each :meth:`~put` used to enqueue a task, a subsequent
        call to :meth:`~task_done` tells the queue that the processing on the
        task is complete.

    .. method:: join(*, [timeout])

        Blocks until all tasks in the queue are done. If *timeout* is specified,
        the method will block for at most *timeout* seconds.

    .. method:: qsize()

        Return the number of items in the queue.

    .. method:: empty()

        Return ``True`` if the queue is empty, ``False`` otherwise.

    .. method:: full()

        Return ``True`` if the queue is full, ``False`` otherwise.


.. class:: AsyncIsraeliQueue[GT, VT](maxsize=None)

    This is the asynchronous implementation of the Israeli Queue. It provides
    group-based task processing and supports non-blocking, asynchronous queue
    operations. The class is designed to work with Python's :mod:`asyncio`
    framework.

    *GT* is the type of the group key. It must be a
    :class:`~collections.abc.Hashable` object. *VT* is the type of the value
    stored in the queue.

    An :class:`AsyncIsraeliQueue` has the following attributes:

    .. attribute:: maxsize

        The maximum number of items that can be placed in the queue. If the
        queue is full, any further attempts to add items will block until space
        becomes available. By default, the queue has no size limit
        (``maxsize=None``).

    An :class:`AsyncIsraeliQueue` instance has the following methods:

    .. method:: put(group, value, /)
        :async:

        Put a value into the queue. If the queue is full, this method will block
        until space becomes available.

        *group* is any :class:`~collections.abc.Hashable` object that represents
        the group to which the value belongs.
        
        *value* is the task to be added to the queue.

        If you wish to specify a timeout, use the :func:`~asyncio.wait_for` function.

    .. method:: put_nowait(group, value, /)

        Put a value into the queue without blocking. If the queue is full, a
        :exc:`~Full` exception is raised.

    .. method:: get()
        :async:

        Remove and return a ``(group, value)`` tuple from the queue. If the queue is empty, this
        method will block until a value becomes available.

        If you wish to specify a timeout, use the :func:`~asyncio.wait_for` function.

    .. method:: get_nowait()
            
        Remove and return an value from the queue without blocking. If the queue
        is empty, an :exc:`~Empty` exception is raised.

    .. method:: get_group()
        :async:

        Remove and return a ``(group, (values, ...))`` tuple from the queue. If the queue is empty, this
        method will block until a value becomes available.

        If you wish to specify a timeout, use the :func:`~asyncio.wait_for` function.

    .. method:: get_group_nowait()
            
        Remove and return a ``(group, (values, ...))`` tuple from the queue without blocking. If the queue
        is empty, an :exc:`~Empty` exception is raised.

    .. method:: task_done()

        Indicate that a formerly enqueued task is complete. Used by queue
        consumers. For each :meth:`~put` used to enqueue a task, a subsequent
        call to :meth:`~task_done` tells

    .. method:: join()
        :async:

        Blocks until all tasks in the queue are done.

        If you wish to specify a timeout, use the :func:`~asyncio.wait_for` function.

    .. method:: qsize()

        Return the number of items in the queue.

    .. method:: empty()

        Return ``True`` if the queue is empty, ``False`` otherwise.

    .. method:: full()

        Return ``True`` if the queue is full, ``False`` otherwise.


Exceptions
----------

.. exception:: Full

    Raised when the queue is full and a new item cannot be added.

.. exception:: Empty

    Raised when the queue is empty and an item cannot be retrieved.
    

Complexity
==========
- **put / put_nowait**: O(1) - Insertion at the end of the queue.
- **get / get_nowait**: O(1) - Dequeueing from the front of the queue.
- **get_group / get_group_nowait**: O(group) - Dequeueing all items from the same group.
- **task_done**: O(1) - Simple bookkeeping to track completed tasks.
- **join**: O(1) - Blocks until all tasks are done.

Benchmarks
----------

The following benchmarks were run on a 2020 MacBook Pro. Each consist of 4000 tasks, with 26 unique groups.

:class:`queue.Queue`::

    python -m timeit -s "from string import ascii_lowercase; from queue import Queue; q = Queue();" "for i in range(4000): q.put((ascii_lowercase[i%26], 'b'))" "for i in range(4000): q.get()"
    50 loops, best of 5: 7.13 msec per loop

:class:`queue.PriorityQueue`::

    python -m timeit -s "from string import ascii_lowercase; from queue import PriorityQueue; pq = PriorityQueue();" "for i in range(4000): pq.put((ascii_lowercase[i%26], 'b'))" "for i in range(4000): pq.get()"
    50 loops, best of 5: 9.52 msec per loop

:class:`queue.SimpleQueue`::

    python -m timeit -s "from string import ascii_lowercase; from queue import SimpleQueue; sq = SimpleQueue();" "for i in range(4000): sq.put((ascii_lowercase[i%26], 'b'))" "for i in range(4000): sq.get()"
    500 loops, best of 5: 654 usec per loop

:class:`israeliqueue.IsraeliQueue`::

    python -m timeit -s "from string import ascii_lowercase; from israeliqueue import IsraeliQueue; iq = IsraeliQueue();" "for i in range(4000): iq.put(ascii_lowercase[i%26], 'b')" "for i in range(4000): iq.get()" 
    50 loops, best of 5: 6.61 msec per loop

As we can see, the :class:`IsraeliQueue` is faster than the built-in :class:`~queue.PriorityQueue` and :class:`~queue.Queue` classes.
That makes sense as the majority of the class is writen in C.

Unlike :class:`~queue.PriorityQueue` the algorithm is O(1) for every operation and so should be fast regardless of the queue size.

The builtin :class:`~queue.SimpleQueue` is the fastest as it is also implemented in C, but it does not support priority queues or any smart handling of queue size and data.

License
=======
This project is licensed under the MIT License.

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
