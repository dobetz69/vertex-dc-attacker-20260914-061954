#!/bin/sh

set +e

if [ -x /code/.venv/bin/python ]; then
  /code/.venv/bin/python /code/mds_census.py
elif command -v python3 >/dev/null 2>&1; then
  python3 /code/mds_census.py
else
  echo "PYTHON_NOT_AVAILABLE"
fi

exit 0
