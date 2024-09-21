# Israeli Queue

## Table of Contents
- [Israeli Queue](#israeli-queue)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [What is an Israeli Queue?](#what-is-an-israeli-queue)
    - [Why is this useful?](#why-is-this-useful)
  - [Installation](#installation)
  - [Classes](#classes)
    - [`IsraeliQueue`](#israeliqueue)
    - [`AsyncIsraeliQueue`](#asyncisraeliqueue)
  - [Documentation](#documentation)
  - [Complexity](#complexity)
  - [Usage](#usage)
    - [Synchronous Example](#synchronous-example)
    - [Asynchronous Example](#asynchronous-example)
  - [License](#license)

## Overview
This project implements a queue system where each item is associated with a "group." The queue processes items in groups, ensuring that items belonging to the same group are dequeued together. This implementation provides both a synchronous version (`IsraeliQueue`) and an asynchronous version (`AsyncIsraeliQueue`) using `asyncio`.

## What is an Israeli Queue?
An Israeli Queue is a type of a priority queue where tasks are grouped together in the same priority. Adding new tasks to the queue will cause them to skip the line and group together. The tasks will then be taken out in-order, group by group.

### Why is this useful?

IsraeliQueues enjoy many benefits from processing grouped tasks in batches. For example, imagine a bot or an API that requires logging in to a remote repository in order to bring files:

```python
def login(repo_name: str):
  return Session("repo_name")  # Expensive operation

def download_file(session: Session, filename: str):
  return Session.download(filename)

def logout(session: Session):
  session.logout
```
Now, we have a thread or an asyncio task that adds files to download to the queue:

```
from israeliqueue import IsraeliQueue
queue = IsraeliQueue()
queue.put("cpython", "build.bat")
queue.put("black", "pyproject.toml")
queue.put("black", "bar")  # Same repo as the second item
queue.put("cpython", "index.html")  # Same repository as the first item
```

An ordinary queue will cause our bot to login and logout four times, processing each item individually.
The IsraeliQueue groups the repositories together, saving setup costs and allowing to download them all in the same request:
```
while True:
  group, items = queue.get_group()
  session = login(group)
  for item in items:
    download_file(session, item)
  logout(session)
```

If the downloading process accepts multiple files at once, it's even more efficient:

```
session.download_files(*items)
```

Other uses may include batching together AWS queries, batching numpy calculations, and plenty more!


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

## Documentation
Full documentation exists on our RTD page.

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
