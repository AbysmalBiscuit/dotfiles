import functools
import re
import sqlite3
from time import *

import numpy as np


a = np.array([])

# COMMENT test
h2: int = 4  # this is a comment
"""this is also a comment"""

# Import test
pattern = re.compile(r)
s = "foo ' \""
s2 = "foo '\""

my_str = (
    r"\d"
    r"\w"
)

re_test: re.Pattern[str] = re.compile(r"^(?P<year>\d{4}) (?P<day>\d) \w\s{,3}")
re_test: re.Pattern[str] = re.compile(
    r"^(?P<year>\d{4}) "
    r"(?P<day>\d) \w\s{,3}"
)
s = r"(?P<day>\d) \w\s{,3}"

db = sqlite3.connect("database.db")

db.execute("""
alter table foo
""")

name = "foo"

query = f"""
SELECT * FROM users WHERE age > 21 AND name = {name};
"""

query = """
ALTER TABLE pineapple
"""

query = """
ANALYZE
"""

query = (
    """
ANALYZE
"""
    "SELECT FROM"
)

query = """ ALTER TABLE pineapple """

string = "This is about my alter table"


def my_wrapper(func, *wrapper_args):
    print(wrapper_args)

    def wrapper(*args, **kwargs):
        start_time = time()
        result = func(*args, **kwargs)
        end_time = time()
        print(f"Function {func.__name__} took {end_time - start_time} seconds")
        return result

    return wrapper


class WrapperContainer:
    @staticmethod
    def wrapper(func):
        return func


# class test


class Hello:
    def __init__(self, x: str):
        self.name = x

    def __str__(self) -> str:
        """Return a string representation of the object."""
        return ""

    def selfprint(self):
        print("hello my name is ", self.name)

    def testprint(self):
        print(1 * 2, 2 + 3, 4 % 5, 8 - 4, 9 / 4, 23 // 4)


functools.reduce()


# Decorators test
class Decorators:
    @classmethod
    def decoratorsTest(cls):
        pass

    @my_wrapper
    def heavy_computation(self, a, b):
        self.var = 1

    @my_wrapper("a", "b")
    def heavy_computation_with_args(self, a, b, c):
        pass

    @functools.cache(1)
    def cached_function(self, a, b):
        pass

    @WrapperContainer.wrapper
    def class_wrapper_func(self):
        pass


my_bool = True

my_num = 1

H1 = Hello("john")
H1.selfprint()
H1.testprint()

my_list = [1, 2, 3]

# list test
a: list[int] = [1, 2, 3, 4, 5]
a.sort()
print(a[1:3])
print(a[:4])
print(a[2])
print(a[2:])

# dictionary test
# copied from w3schools example

myfamily = {
    "child1": {"name": "Emil", "year": 2004},
    "child2": {"name": "Tobias", "year": 2007},
    "child3": {"name": "Linus", "year": 2011},
}

# tuple test

testTuple = ("one", 2, "3")
print(testTuple)

print(np.random.randint(5, 45))


l = [0, 1, 2]

#

# string test
# a = "hello world"
b = """good morning
hello world
bye"""

formattest = f"teststring is ={5}"

# lambda test


def x2(n):
    lambda n: n / 7


# if else ladder
if 1 > 2:
    print("yes")
elif 4 > 5:
    print("maybe")
else:
    print("no")

# loops
i = 5
while i > 0:
    print(i)
    i -= 1

for x in range(1, 20, 2):
    print(x)
