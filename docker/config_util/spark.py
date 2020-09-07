from pyspark.sql import SparkSession
import os
from .opts import calculate_spark_options


def initSpark():
    builder = SparkSession.builder
    for name, value in calculate_spark_options().items():
        builder = builder.config(name, value)
    return builder.getOrCreate()