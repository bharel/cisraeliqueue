from collections.abc import Hashable, Set
from typing import Generic, TypeVar

type Timeout = float | None
GT = TypeVar("GT", bound=Hashable)
VT = TypeVar("VT", bound=object)

class _IsraeliQueue(Generic[GT, VT]):
    maxsize: int | None
    def __init__(self, maxsize: int | None = None, /) -> None: ...
    def qsize(self) -> int: ...
    def empty(self) -> bool: ...
    def full(self) -> bool: ...
    def groups(self) -> Set[GT]: ...
    def unfinished_tasks(self) -> int: ...
    def __repr__(self) -> str: ...

class IsraeliQueue(_IsraeliQueue[GT, VT]):
    def put(self, group: GT, value: VT, /, *, timeout: Timeout) -> None: ...
    def put_nowait(self, group: GT, value: VT, /) -> None: ...
    def get(self, *, timeout: Timeout) -> tuple[GT, VT]: ...
    def get_nowait(self) -> tuple[GT, VT]: ...
    def get_group(self, *, timeout: Timeout) -> tuple[GT, tuple[VT, ...]]: ...
    def get_group_nowait(self) -> tuple[GT, tuple[VT, ...]]: ...
    def task_done(self) -> None: ...
    def join(self, *, timeout: Timeout) -> None: ...

class Empty(Exception): ...
class Full(Exception): ...
class Shutdown(Exception): ...

class AsyncIsraeliQueue(_IsraeliQueue[GT, VT]):
    async def put(self, group: GT, value: VT, /) -> None: ...
    def put_nowait(self, group: GT, value: VT, /) -> None: ...
    async def get(self) -> tuple[GT, VT]: ...
    def get_nowait(self) -> tuple[GT, VT]: ...
    async def get_group(self) -> tuple[GT, tuple[VT, ...]]: ...
    def get_group_nowait(self) -> tuple[GT, tuple[VT, ...]]: ...
    def task_done(self) -> None: ...
    async def join(self) -> None: ...
