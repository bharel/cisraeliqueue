import os
from israeliqueue import IsraeliQueue, Empty, Full, AsyncIsraeliQueue
from unittest import IsolatedAsyncioTestCase, TestCase
import time
import threading
import asyncio

TIMEOUT = 1 if os.getenv("CI") else 0.2
DELTA = TIMEOUT / 4


class IsraeliQueueTestCase(TestCase):
    def setUp(self) -> None:
        self.q = IsraeliQueue()
        return super().setUp()

    def test_put(self):
        self.q.put("group", "value1", timeout=0.1)
        self.q.put("group1", "value2", timeout=None)
        self.q.put_nowait("group", "value3")

        self.assertEqual(self.q.get_group(), ("group", ("value1", "value3")))
        self.assertEqual(self.q.get(), ("group1", "value2"))

    def test_put_timeout(self):
        self.q.maxsize = 1
        self.q.put("group", "value1")
        start_time = time.monotonic()
        self.assertRaises(Full, self.q.put, "group", "value2", timeout=TIMEOUT)
        self.assertAlmostEqual(
            time.monotonic() - start_time, TIMEOUT, delta=DELTA
        )

    def test_deallocation(self):
        """Make sure that the queue deallocates properly when deleted"""
        counter = 0

        class A:
            def __del__(self):
                nonlocal counter
                counter += 1

        self.q.put("group", A())
        self.assertEqual(counter, 0)
        del self.q
        self.assertEqual(counter, 1)

    def test_get_timeout(self):
        start_time = time.monotonic()
        self.assertRaises(Empty, self.q.get, timeout=TIMEOUT)
        self.assertAlmostEqual(
            time.monotonic() - start_time, TIMEOUT, delta=DELTA
        )

    def test_get_group_nowait(self):
        self.assertRaises(Empty, self.q.get_group_nowait)
        self.q.put("group", "value1")
        self.q.put("group", "value2")
        self.assertEqual(
            self.q.get_group_nowait(), ("group", ("value1", "value2"))
        )

    def test_get_group_timeout(self):
        start_time = time.monotonic()
        self.assertRaises(Empty, self.q.get_group, timeout=TIMEOUT)
        self.assertAlmostEqual(
            time.monotonic() - start_time, TIMEOUT, delta=DELTA
        )

    def test_join(self):
        self.q.put("group", "value1")
        self.q.put("group", "value2")
        self.q.task_done()
        self.q.task_done()
        self.q.join()  # Make sure .join() is called while not waiting
        self.q.put("group", "value2")

        # Make sure .join() is called while waiting
        def task_done():
            time.sleep(TIMEOUT)
            self.q.task_done()

        start_time = time.monotonic()
        threading.Thread(target=task_done).start()
        self.q.join()
        self.assertAlmostEqual(
            time.monotonic() - start_time, TIMEOUT, delta=DELTA
        )

    def test_join_timeout(self):
        self.q.put("group", "value1")
        self.q.put("group", "value2")
        self.q.task_done()
        start_time = time.monotonic()
        with self.assertRaises(TimeoutError):
            self.q.join(timeout=TIMEOUT)
        self.assertAlmostEqual(
            time.monotonic() - start_time, TIMEOUT, delta=DELTA
        )

    def test_qszie(self):
        self.q.put("group", "value1")
        self.q.put("group", "value2")
        self.assertEqual(self.q.qsize(), 2)

    def test_empty(self):
        self.assertTrue(self.q.empty())
        self.q.put("group", "value1")
        self.assertFalse(self.q.empty())

    def test_full(self):
        self.q.maxsize = 1
        self.q.put("group", "value1")
        self.assertTrue(self.q.full())

    def test_maxsize_none(self):
        self.assertIsNone(self.q.maxsize)
        self.q.put("group", "value1")
        self.q.put("group", "value2")
        self.q.maxsize = 1
        self.assertTrue(self.q.full())
        self.q.maxsize = None
        self.assertFalse(self.q.full())

    def test_init(self):
        q = IsraeliQueue(1)
        self.assertEqual(q.maxsize, 1)
        q = IsraeliQueue()
        self.assertIsNone(q.maxsize)


class AsyncIsraeliQueueTestCase(IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.q = AsyncIsraeliQueue()
        return super().setUp()

    async def test_put(self):
        await self.q.put("group", "value1")
        await self.q.put("group1", "value2")
        self.q.put_nowait("group", "value3")

        self.assertEqual(
            await self.q.get_group(), ("group", ("value1", "value3"))
        )
        self.assertEqual(await self.q.get(), ("group1", "value2"))

    async def test_put_full(self):
        self.q.maxsize = 1
        await self.q.put("group", "value1")
        with self.assertRaises(Full):
            self.q.put_nowait("group", "value2")
        self.q.get_nowait()
        self.q.put_nowait("group", "value2")

    async def test_get_empty(self):
        with self.assertRaises(Empty):
            self.q.get_nowait()
        await self.q.put("group", "value1")
        self.q.get_nowait()

    async def test_join(self):
        await self.q.put("group", "value1")
        await self.q.put("group", "value2")
        self.q.task_done()
        self.q.task_done()
        await self.q.join()

        self.q.put_nowait("group", "value2")

        async def task_done():
            await asyncio.sleep(TIMEOUT)
            self.q.task_done()

        start_time = time.monotonic()
        asyncio.create_task(task_done())
        await self.q.join()
        self.assertAlmostEqual(
            time.monotonic() - start_time, TIMEOUT, delta=DELTA
        )

    def test_get_group_nowait(self):
        with self.assertRaises(Empty):
            self.q.get_group_nowait()
        self.q.put_nowait("group", "value1")
        self.q.put_nowait("group", "value2")
        self.assertEqual(
            self.q.get_group_nowait(), ("group", ("value1", "value2"))
        )

    def test_qszie(self):
        self.q.put_nowait("group", "value1")
        self.q.put_nowait("group", "value2")
        self.assertEqual(self.q.qsize(), 2)

    def test_empty(self):
        self.assertTrue(self.q.empty())
        self.q.put_nowait("group", "value1")
        self.assertFalse(self.q.empty())

    def test_full(self):
        self.q.maxsize = 1
        self.q.put_nowait("group", "value1")
        self.assertTrue(self.q.full())

    def test_maxsize_none(self):
        self.assertIsNone(self.q.maxsize)
        self.q.put_nowait("group", "value1")
        self.q.put_nowait("group", "value2")
        self.q.maxsize = 1
        self.assertTrue(self.q.full())
        self.q.maxsize = None
        self.assertFalse(self.q.full())

    def test_init(self):
        q = AsyncIsraeliQueue(1)
        self.assertEqual(q.maxsize, 1)
        q = AsyncIsraeliQueue()
        self.assertIsNone(q.maxsize)
