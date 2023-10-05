import boto3
import datetime

DYNAMODB_TABLE_NAME = 'AndriiBtDemoStorage'
region = 'us-east-1'

def get_autoscaling_groups(region):
    autoscaling_client = boto3.client('autoscaling', region_name=region)
    return autoscaling_client.describe_auto_scaling_groups()['AutoScalingGroups']

def get_current_time():
    return datetime.datetime.now()

def parse_time_ranges(time_ranges):
    return [tuple(map(lambda x: datetime.datetime.strptime(x, '%H:%M').time(), tr.split('-'))) for tr in time_ranges]

def is_current_time_in_ranges(current_time, time_ranges):
    for start_time, end_time in time_ranges:
        if start_time <= current_time <= end_time:
            return f"{start_time.strftime('%H:%M')}-{end_time.strftime('%H:%M')}"
    return None

def update_autoscaling_group(asg_name, min_capacity, desired_capacity, region):
    autoscaling_client = boto3.client('autoscaling', region_name=region)
    autoscaling_client.update_auto_scaling_group(
        AutoScalingGroupName=asg_name,
        MinSize=int(min_capacity),
        DesiredCapacity=int(desired_capacity)
    )

def save_to_dynamodb(table, asg_name, min_capacity, desired_capacity, last_update_time, current_time_slot):
    table.put_item(
        Item={
            'ASGName': asg_name,
            'MinCapacity': int(min_capacity),
            'DesiredCapacity': int(desired_capacity),
            'LastUpdateTime': last_update_time,
            'CurrentTimeSlot': current_time_slot
        }
    )

def get_from_dynamodb(table, asg_name):
    response = table.get_item(
        Key={
            'ASGName': asg_name
        }
    )
    return response.get('Item')

def lambda_handler(event, context):
    dynamodb = boto3.resource('dynamodb', region_name=region)
    dynamodb_table = dynamodb.Table(DYNAMODB_TABLE_NAME)

    autoscaling_groups = get_autoscaling_groups(region)
    current_time = get_current_time()

    for asg in autoscaling_groups:
        asg_name = asg['AutoScalingGroupName']
        non_working_hours_tag = next((tag for tag in asg.get('Tags', []) if tag['Key'] == 'non_working_hours'), None)
        print(f"Checking {asg_name}")

        if non_working_hours_tag is None:
            print(f"Skip {asg_name}")
            continue

        if non_working_hours_tag:
            time_ranges = parse_time_ranges(non_working_hours_tag['Value'].split(','))
            current_time_slot = is_current_time_in_ranges(current_time.time(), time_ranges)
            dynamodb_values = get_from_dynamodb(dynamodb_table, asg_name)

            if current_time_slot:
                # Check if the ASG has already been scaled down during this time slot
                if dynamodb_values and dynamodb_values['CurrentTimeSlot'] == current_time_slot and (current_time - datetime.datetime.strptime(dynamodb_values['LastUpdateTime'], '%Y-%m-%d %H:%M:%S.%f')).total_seconds() < 24 * 60 * 60:
                    print(f"ASG {asg_name}: Already scaled down during this time slot. Skipping.")
                    continue
                # Save current values to DynamoDB
                save_to_dynamodb(dynamodb_table, asg_name, asg['MinSize'], asg['DesiredCapacity'], str(current_time), current_time_slot)
                update_autoscaling_group(asg_name, 0, 0, region)
                print(f"Operation: Set min and desired capacity to 0 for ASG {asg_name} {current_time_slot}. Save MinSize={asg['MinSize']} DesiredCapacity={asg['DesiredCapacity']}")
            else:
                if dynamodb_values and 'DesiredCapacity' in dynamodb_values and dynamodb_values['DesiredCapacity'] > 0:
                    update_autoscaling_group(asg_name, dynamodb_values['MinCapacity'], dynamodb_values['DesiredCapacity'], region)
                    print(f"Operation: Restored min and desired capacity from DynamoDB for ASG {asg_name} MinCapacity={dynamodb_values['MinCapacity']} DesiredCapacity={dynamodb_values['DesiredCapacity']}.")
                else:
                    print(f"Skip any action for ASG {asg_name}.")

    print("Lambda execution completed.")
