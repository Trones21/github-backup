# local_run.py
import json
from lambda_function import lambda_handler


if __name__ == "__main__":
    # minimal event/context for local testing
    result = lambda_handler(event={}, context=None)
    print(json.dumps(result, indent=2, default=str))
