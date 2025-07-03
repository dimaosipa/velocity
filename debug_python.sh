#!/bin/bash

# Debug script for Python framework issues
# This script will help diagnose why Python binaries are being killed

echo "=== Python Framework Debug Script ===" > debug_output.txt
echo "Date: $(date)" >> debug_output.txt
echo "" >> debug_output.txt

# Check if Python framework library exists and basic info
echo "1. Python Framework Library Info:" >> debug_output.txt
ls -la /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/Python >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check install name
echo "2. Python Framework Install Name:" >> debug_output.txt
otool -D /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/Python >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check dependencies
echo "3. Python Framework Dependencies:" >> debug_output.txt
otool -L /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/Python >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check @rpath entries
echo "4. Python Framework @rpath entries:" >> debug_output.txt
otool -l /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/Python | grep -A 2 LC_RPATH >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check Python binary info
echo "5. Python Binary Info:" >> debug_output.txt
ls -la /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/python3.13 >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check Python binary dependencies
echo "6. Python Binary Dependencies:" >> debug_output.txt
otool -L /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/python3.13 >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check Python binary @rpath entries
echo "7. Python Binary @rpath entries:" >> debug_output.txt
otool -l /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/python3.13 | grep -A 2 LC_RPATH >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check code signature status
echo "8. Code Signature Status:" >> debug_output.txt
codesign -v /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/Python >> debug_output.txt 2>&1
echo "" >> debug_output.txt
codesign -v /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/python3.13 >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Try to find any files with invalid signatures
echo "9. Framework Directory Contents:" >> debug_output.txt
find /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks -type f -name "*.dylib" -o -name "Python" | head -5 >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Check system Python for comparison
echo "10. System Python for comparison:" >> debug_output.txt
which python3 >> debug_output.txt 2>&1
/usr/bin/python3 --version >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Try to run with different DYLD settings to see what happens
echo "11. Attempting Python execution with debug output:" >> debug_output.txt
echo "This might be killed, but let's capture what we can..." >> debug_output.txt

# Capture any crash logs
echo "12. Recent crash logs for python:" >> debug_output.txt
ls -la ~/Library/Logs/DiagnosticReports/*python* 2>/dev/null | tail -3 >> debug_output.txt 2>&1
echo "" >> debug_output.txt

# Try with minimal environment
echo "13. Testing with timeout and minimal environment:" >> debug_output.txt
timeout 2s /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/python3.13 --version >> debug_output.txt 2>&1
echo "Exit code: $?" >> debug_output.txt
echo "" >> debug_output.txt

# Check if the issue is with the binary itself or framework loading
echo "14. File type check:" >> debug_output.txt
file /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/python3.13 >> debug_output.txt 2>&1
file /Users/dmitry/.velo/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/Python >> debug_output.txt 2>&1
echo "" >> debug_output.txt

echo "=== Debug script completed ===" >> debug_output.txt
echo "Results saved to debug_output.txt"