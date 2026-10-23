#!/usr/bin/env python3
"""Restore interactive signals before replacing a Bash asynchronous job with SBX."""
import os
import signal
import sys


signal.signal(signal.SIGINT, signal.SIG_DFL)
signal.signal(signal.SIGQUIT, signal.SIG_DFL)
os.execvp("sbx", ["sbx", *sys.argv[1:]])
