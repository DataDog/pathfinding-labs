#!/usr/bin/env python3
"""Test network discovery in demos and solutions without AWS credentials or calls.

Run: python3 -m unittest discover -s scripts/tests -p 'test_network_discovery.py'
Only the marked discovery block is executed, never the full demo or solution.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = (
    'ec2-001-', 'ec2-004-', 'ecs-001-', 'ecs-002-', 'ecs-003-',
    'ecs-004-', 'ecs-008-', 'sts-001-to-ecs-002-to-admin',
)
START = '# Discover the custom network deployed by the prod environment.'
END = '# End Pathfinding network discovery.'

# This stub returns the text output of the supported Describe calls. It fails
# on unexpected filters/queries and cannot call AWS or launch a workload.
STUB = r'''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
assert args[0] == 'ec2', args
op = args[1]
assert op in ('describe-vpcs', 'describe-subnets'), args
if '--region' in args:
    assert args[args.index('--region') + 1] == 'us-east-1', args
assert args[args.index('--output') + 1] == 'text', args
start = args.index('--filters') + 1
end = args.index('--query')
filters = set(args[start:end])
query = args[end + 1]
mode = os.environ['NETWORK_CASE']
if op == 'describe-vpcs':
    assert query == 'Vpcs[].VpcId', args
    assert filters == {'Name=tag:Name,Values=pathfinding', 'Name=is-default,Values=false'}, args
    if mode == 'vpc_api_error':
        sys.exit(254)
    if mode in ('missing_vpc', 'default_only'):
        print('')
    elif mode == 'duplicate_vpc':
        print('vpc-12345678\tvpc-87654321')
    elif mode == 'none_vpc':
        print('None')
    else:
        # With an unrelated default VPC present, the filters still return only
        # the custom Pathfinding VPC.
        print('vpc-12345678')
else:
    assert query == 'Subnets[].SubnetId', args
    base = {'Name=vpc-id,Values=vpc-12345678', 'Name=map-public-ip-on-launch,Values=true'}
    names = filters - base
    assert base <= filters and len(names) == 1, args
    name = names.pop()
    assert name in ('Name=tag:Name,Values=pathfinding Operational Subnet 1',
                    'Name=tag:Name,Values=pathfinding Operational Subnet 2'), args
    if mode == 'subnet_api_error':
        sys.exit(254)
    if mode in ('missing_subnet', 'private_subnet') or (mode == 'missing_second' and name.endswith('2')):
        print('')
    elif mode == 'duplicate_subnet':
        print('subnet-12345678\tsubnet-87654321')
    elif mode == 'none_subnet':
        print('None')
    else:
        print('subnet-87654321' if name.endswith('2') else 'subnet-12345678')
'''


class NetworkDiscoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blocks = []
        for directory in sorted((ROOT / 'modules/scenarios').rglob('*')):
            if directory.is_dir() and directory.name.startswith(SCENARIOS):
                for name in ('demo_attack.sh', 'solution.md'):
                    path = directory / name
                    text = path.read_text()
                    assert text.count(START) == text.count(END) == 1, path
                    block = text.split(START, 1)[1].split(END, 1)[0]
                    cls.blocks.append((path, block))
        assert len(cls.blocks) == 16, len(cls.blocks)

    def run_case(self, mode, success, second_only=False):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / 'aws'
            fake.write_text(STUB)
            fake.chmod(0o755)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'],
                       NETWORK_CASE=mode, AWS_REGION='us-east-1')
            for path, block in self.blocks:
                if second_only and 'SUBNET_2=' not in block:
                    continue
                with self.subTest(case=mode, source=str(path.relative_to(ROOT))):
                    script = 'show_cmd() { :; }\n' + block + '\necho DISCOVERY_SUCCEEDED\n'
                    result = subprocess.run(['/bin/bash', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode == 0, success, result.stderr)
                    self.assertEqual('DISCOVERY_SUCCEEDED' in result.stdout, success)
                    if success:
                        self.assertIn('vpc-12345678', result.stdout)
                        self.assertIn('subnet-12345678', result.stdout)
                        if 'SUBNET_2=' in block:
                            self.assertIn('subnet-87654321', result.stdout)

    def test_custom_network_without_default_vpc(self):
        self.run_case('custom_only', True)

    def test_custom_network_with_default_vpc(self):
        self.run_case('with_default', True)

    def test_reject_missing_ambiguous_or_failed_discovery(self):
        for mode in ('missing_vpc', 'default_only', 'duplicate_vpc', 'none_vpc',
                     'vpc_api_error', 'missing_subnet', 'private_subnet',
                     'duplicate_subnet', 'none_subnet', 'subnet_api_error'):
            self.run_case(mode, False)

    def test_service_demo_requires_second_subnet(self):
        self.run_case('missing_second', False, second_only=True)

    def test_demo_shell_syntax(self):
        for path, _ in self.blocks:
            if path.suffix == '.sh':
                with self.subTest(source=str(path.relative_to(ROOT))):
                    subprocess.run(['/bin/bash', '-n', str(path)], check=True)


if __name__ == '__main__':
    unittest.main()
