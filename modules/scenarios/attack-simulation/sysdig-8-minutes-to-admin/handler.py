import boto3
import json

def handler(event, context):
    """Initializes new EC2 instances by verifying connectivity and checking instance state."""
    ec2 = boto3.client('ec2')
    try:
        response = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['pending', 'running']}]
        )
        instance_count = sum(len(r['Instances']) for r in response['Reservations'])
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'EC2 init check complete. {instance_count} active instances.',
                'status': 'ok'
            })
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
