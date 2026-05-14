# local_run.py
import json
import logging

# Surface INFO-level progress logs from lambda_function. In Lambda the runtime
# attaches a handler automatically; locally we have to do it ourselves.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)

from lambda_function import lambda_handler  # noqa: E402


if __name__ == "__main__":
    result = lambda_handler(event={}, context=None)
    print(json.dumps(result, indent=2, default=str))
