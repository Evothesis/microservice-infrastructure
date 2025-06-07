import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    export Lambda function
    Environment: dev
    """
    logger.info(f"Event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps({
            'message': 'export is working',
            'environment': 'dev',
            'timestamp': datetime.utcnow().isoformat()
        })
    }
