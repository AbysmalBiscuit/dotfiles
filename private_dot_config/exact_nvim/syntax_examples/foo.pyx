# cython: language_level=3
"""
Created on 2021-07-10 17:36

@author: Lev Velykoivanenko (velykoivanenko.lev@gmail.com)
"""
import cython
import scipy.stats

import numpy as np
cimport numpy as np

from numpy cimport ndarray, float64_t


cdef class Demand:
    def __init__(self, str distribution, dict distribution_params, double cov_demand):
        self.distribution_name = distribution
        if distribution_params is None:
            distribution_params = dict()
        self.distribution_params = distribution_params
        self.cov_demand = cov_demand

        if not hasattr(scipy.stats, distribution):
            raise ValueError(f"Received an unknown distribution name: {distribution}")
        self.distribution = getattr(scipy.stats, distribution)
        self.ppf = self.distribution.ppf

    cpdef double draw_sample(self, dict kwargs):
        if len(kwargs) > 0:
            self.distribution_params.update(kwargs)
        return fmaxl(self.distribution.ppf(np.random.random(), **self.distribution_params), 0.0)

    cdef double cdraw_sample(self, dict kwargs):
        if len(kwargs) > 0:
            self.distribution_params.update(kwargs)
        return fmaxl(self.distribution.ppf(np.random.random(), **self.distribution_params), 0.0)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef ndarray[float64_t, ndim=1] fill_array(self, ndarray[float64_t, ndim=1] ref_array):
        cdef dict ref_kwargs = self.distribution_params
        cdef ndarray[float64_t, ndim=1] array = np.ndarray(ref_array.shape[0], dtype=np.float64)
        for i in range(len(ref_array)):
            ref_kwargs["loc"] = ref_array[i]
            ref_kwargs["scale"] = ref_array[i] * self.cov_demand
            array[i] = fmaxl(self.ppf(np.random.random(), **self.distribution_params), 0.0)
        return array
