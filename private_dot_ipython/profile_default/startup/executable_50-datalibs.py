#!/usr/bin/env python3
"""
Created on 2020-12-13 09:00

@author: Lev Velykoivanenko (velykoivanenko.lev@gmail.com)
"""

try:
    import numexpr as ne
    import numpy as np
    import pandas as pd
    import matplotlib.pyplot as plt
except ImportError:
    import sys

    print("Failed to import one or more of the following modules:", file=sys.stderr)
    print("\n".join(["numexpr", "numpy", "pandas", "matplotlib"]))
