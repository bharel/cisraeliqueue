# Israeli Queue

## Table of Contents
1. [Overview](#overview)
2. [What is an Israeli Queue?](#what-is-an-israeli-queue)
3. [Installation](#installation)
4. [Classes](#classes)
   - [IsraeliQueue](#israeliqueue)
   - [AsyncIsraeliQueue](#asyncisraeliqueue)
5. [Public Methods and Attributes](#public-methods-and-attributes)
   - [IsraeliQueue](#israeliqueue-methods)
   - [AsyncIsraeliQueue](#asyncisraeliqueue-methods)
6. [Complexity](#complexity)
7. [Usage](#usage)

## Overview
This project implements a queue system where each item is associated with a "group." The queue processes items in groups, ensuring that items belonging to the same group are dequeued together. This implementation provides both a synchronous version (`IsraeliQueue`) and an asynchronous version (`AsyncIsraeliQueue`) using `asyncio`.

## What is an Israeli Queue?
An Israeli Queue is a group-prioritized queue system where individuals (or tasks) are grouped, and when one member of a group enters the queue, other members of that group are allowed to bypass some of the queue to join them. This queue type simulates real-world scenarios where group members receive priority to stay together, such as friends in line at a concert or airport check-in.

In the context of this implementation, the concept of an "Israeli Queue" is applied to tasks where the queue processes grouped tasks together, ensuring that once a task in a group is dequeued, the rest of the tasks in that group are processed consecutively.

## Installation
To install the package, simply `pip install cisraeliqueue`.

You can use the classes in your project as follows:

```python
from israeliqueue import IsraeliQueue, AsyncIsraeliQueue
```

## Classes

### `IsraeliQueue`
This is the synchronous implementation of the Israeli Queue. It provides group-based task processing and supports both blocking and non-blocking queue operations. The class is thread-safe and can be used in multithreaded environments.

### `AsyncIsraeliQueue`
This is the asynchronous version of the Israeli Queue, built using Python's `asyncio` framework. It provides non-blocking, asynchronous methods for queue operations and is suitable for applications requiring high concurrency and asynchronous task management.

---

## Public Methods and Attributes

### `IsraeliQueue` Methods
#### **`__init__(self, maxsize: int = UINT_MAX)`**
Initializes the queue with an optional `maxsize` parameter. If the queue reaches `maxsize`, further inserts will block until space becomes available.

- **Parameters**: 
  - `maxsize` (int, optional): Maximum number of items the queue can hold. Defaults to `UINT_MAX`.

#### **`put(self, group: _GT, value: _VT, timeout: float | None = None)`**
Adds an item associated with a group to the queue. If the queue is full, it will block until space becomes available.

- **Parameters**: 
  - `group` (_GT): The group identifier for the item.
  - `value` (_VT): The value to add to the queue.
  - `timeout` (float, optional): Maximum time to wait for space to become available.

#### **`put_nowait(self, group: _GT, value: _VT)`**
Adds an item to the queue without blocking. Raises `Full` if the queue is full.

#### **`get(self, timeout: float | None = None)`**
Removes and returns a tuple of a group and its associated item from the queue. If the queue is empty, it blocks until an item is available.

- **Returns**: 
  - Tuple containing the group and the item.
  - Raises `Empty` if the queue is empty after the timeout.

#### **`get_nowait(self)`**
Removes and returns an item without blocking. Raises `Empty` if the queue is empty.

#### **`get_group(self, timeout: float | None = None)`**
Removes and returns all items from the queue that belong to the same group.

- **Returns**: 
  - A tuple containing the group and a tuple of items removed from the queue.
  - Raises `Empty` if the queue is empty.

#### **`get_group_nowait(self)`**
Removes and returns all items from the queue that belong to the same group, without blocking. Raises `Empty` if the queue is empty.

#### **`task_done(self)`**
Indicates that a previously enqueued task has been completed. This method is used to signal that queue consumers have processed a task.

#### **`join(self, timeout: float | None = None)`**
Blocks until all items in the queue have been processed. Raises `TimeoutError` if the timeout is reached before all tasks are done.

---

### `AsyncIsraeliQueue` Methods
#### **`__init__(self, maxsize: int = UINT_MAX)`**
Initializes the asynchronous queue with an optional `maxsize`. Works similarly to `IsraeliQueue`.

#### **`async put(self, group: Hashable, value: object)`**
Adds an item associated with a group to the queue. If the queue is full, it waits asynchronously until space becomes available.

#### **`put_nowait(self, group: Hashable, value: object)`**
Adds an item to the queue without blocking. Raises `Full` if the queue is full.

#### **`async get(self)`**
Removes and returns an item from the queue. If the queue is empty, it waits asynchronously until an item is available.

- **Returns**: 
  - A tuple containing the group and the item.

#### **`get_nowait(self)`**
Removes and returns an item from the queue without blocking. Raises `Empty` if the queue is empty.

#### **`async get_group(self)`**
Removes and returns all items from the queue that belong to the same group. Waits asynchronously if the queue is empty.

#### **`get_group_nowait(self)`**
Removes and returns all items from the queue that belong to the same group, without blocking. Raises `Empty` if the queue is empty.

#### **`task_done(self)`**
Marks a task as completed, similar to `IsraeliQueue`.

#### **`async join(self)`**
Blocks asynchronously until all items in the queue have been processed.

---

## Complexity

- **put / put_nowait**: O(1) - Insertion at the end of the queue.
- **get / get_nowait**: O(1) - Dequeueing from the front of the queue.
- **get_group / get_group_nowait**: O(group) - Dequeueing all items from the same group.
- **task_done**: O(1) - Simple bookkeeping to track completed tasks.
- **join**: O(1) - Blocks until all tasks are done

---

## Usage

### Synchronous Example

```python
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
```

### Asynchronous Example

```python
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
```

---

## License
This project is licensed under the MIT License.
```