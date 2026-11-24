#!/usr/bin/env python3
"""Read one JSON action per line; keep a temporary UHID device until EOF."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

NAME = 'Home Organizer Control'


def validate(action, width, height):
    if not isinstance(action, dict):
        raise ValueError('Action must be an object')
    op = action.get('op')
    fields = {
        'tap': {'op', 'x', 'y'},
        'drag': {'op', 'x', 'y', 'to_x', 'to_y', 'hold', 'settle'},
        'swipe': {'op', 'x', 'y', 'to_x', 'to_y'},
        'text': {'op', 'value', 'package', 'resource', 'select_all'},
    }
    if op not in fields or set(action) - fields[op]:
        raise ValueError('Unknown action or field')
    if op == 'text':
        value = action.get('value')
        if not isinstance(value, str) or not value or len(value) > 80:
            raise ValueError('Text must contain 1 to 80 characters')
        if not all(c in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ' for c in value):
            raise ValueError('Use the on-screen keyboard for other characters')
        if not all(isinstance(action.get(k), str) and action[k] for k in ('package', 'resource')):
            raise ValueError('Text requires an expected package and resource ID')
        if 'select_all' in action and type(action['select_all']) is not bool:
            raise ValueError('select_all must be boolean')
    else:
        points = [('x', width), ('y', height)]
        if op != 'tap':
            points += [('to_x', width), ('to_y', height)]
        for key, limit in points:
            n = action.get(key)
            if type(n) not in (int, float) or not math.isfinite(n) or not 0 <= n < limit:
                raise ValueError('Coordinate outside the observed display')
        for key in ('hold', 'settle'):
            if key in action:
                n = action[key]
                if type(n) not in (int, float) or not math.isfinite(n) or not 0 <= n <= 5:
                    raise ValueError('Timing must be between zero and five seconds')
    return action


def focused_editor(xml, package, resource):
    return any(n.get('package') == package and n.get('resource-id') == resource
               and n.get('class') == 'android.widget.EditText'
               and n.get('focused') == 'true' and n.get('enabled') == 'true'
               and n.get('password') != 'true'
               for n in ET.fromstring(xml).iter('node'))


class Controller:
    def __init__(self, serial, binary, width, height):
        self.adb = ['adb', '-s', serial]
        self.binary = str(Path(binary).resolve())
        self.width, self.height = width, height
        self.remote = None
        self.process = None

    def adb_run(self, *args):
        return subprocess.check_output(self.adb + list(args), timeout=20, text=True)

    def reply(self):
        if not select.select([self.process.stdout], [], [], 10)[0]:
            raise RuntimeError('UHID response timed out')
        return self.process.stdout.readline().strip()

    def start(self):
        remote = self.adb_run('shell', 'mktemp', '-d', '/data/local/tmp/home-organizer.XXXXXX').strip()
        if not re.fullmatch(r'/data/local/tmp/home-organizer\.[A-Za-z0-9]+', remote):
            raise RuntimeError('Unexpected temporary directory')
        self.remote = remote
        self.adb_run('push', self.binary, remote + '/control')
        self.adb_run('shell', 'chmod', '700', remote + '/control')
        self.process = subprocess.Popen(self.adb + ['shell', '-T', remote + '/control'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        if self.reply() != 'ready':
            raise RuntimeError('UHID could not be opened with current shell permissions')
        for _ in range(20):
            state = self.adb_run('shell', 'dumpsys', 'input')
            match = re.search(r'Device \d+: ' + re.escape(NAME) + r'\n(.*?)(?=\n  Device |\Z)', state, re.S)
            if match and 'Sources: TOUCHSCREEN' in match[1]:
                self.check_display(state)
                return
            time.sleep(.3)
        raise RuntimeError('Virtual device was not recognized as a touchscreen')

    def check_display(self, state=None):
        state = state or self.adb_run('shell', 'dumpsys', 'input')
        viewports = re.findall(r'Viewport INTERNAL:.*', state)
        expected = f'logicalFrame=[0, 0, {self.width}, {self.height}]'
        if not any('orientation=0,' in v and expected in v and 'isActive=[1]' in v for v in viewports):
            raise RuntimeError('Display changed or is unsupported; inspect a fresh screenshot')

    def report(self, message):
        self.process.stdin.write(message + '\n')
        self.process.stdin.flush()
        if self.reply() != 'ok':
            raise RuntimeError('UHID report failed')

    def touch(self, down, x, y):
        self.report(f't {down} {round(x * 32767 / self.width)} {round(y * 32767 / self.height)}')

    def key(self, usage, modifier=0):
        self.report(f'k {modifier} {usage} 0')
        time.sleep(.04)
        self.report('k 0 0 0')
        time.sleep(.04)

    def action(self, action):
        validate(action, self.width, self.height)
        self.check_display()
        op = action['op']
        if op == 'text':
            path = self.remote + '/window.xml'
            self.adb_run('shell', 'uiautomator', 'dump', path)
            xml = self.adb_run('shell', 'cat', path)
            if not focused_editor(xml, action['package'], action['resource']):
                raise RuntimeError('Expected editable field is not focused; no text sent')
            if action.get('select_all', False):
                self.key(4, 1)
            for char in action['value']:
                if char.isalpha():
                    self.key(ord(char.lower()) - ord('a') + 4, 2 if char.isupper() else 0)
                elif char.isdigit():
                    self.key(39 if char == '0' else 29 + int(char))
                else:
                    self.key(44)
            # Never send Enter: the operator must inspect and confirm the field.
        else:
            x, y = action['x'], action['y']
            self.touch(1, x, y)
            try:
                if op == 'tap':
                    time.sleep(.09)
                else:
                    time.sleep(action.get('hold', .85) if op == 'drag' else .05)
                    end_x, end_y = action['to_x'], action['to_y']
                    start_x, start_y = x, y
                    for i in range(1, 21):
                        x = start_x + (end_x - start_x) * i / 20
                        y = start_y + (end_y - start_y) * i / 20
                        self.touch(1, x, y)
                        time.sleep(.025)
                    time.sleep(action.get('settle', .6) if op == 'drag' else .04)
            finally:
                self.touch(0, x, y)
        time.sleep(.4)

    def close(self):
        if self.process:
            try:
                self.process.stdin.close()
                self.process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        if self.remote:
            self.adb_run('shell', 'rm', '-rf', self.remote)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default=os.environ.get('ANDROID_SERIAL'))
    parser.add_argument('--binary', help='Android-native executable compiled from uhid-control.c')
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    parser.add_argument('--probe', action='store_true', help='Register and remove the device without sending input')
    parser.add_argument('--dry-run', action='store_true', help='Validate JSON only; do not call ADB')
    args = parser.parse_args()
    if args.width < 2 or args.height < 2:
        parser.error('Display dimensions must be positive and greater than one')
    if not args.dry_run and (not args.serial or not args.binary):
        parser.error('--serial and --binary are required for live use')
    controller = None
    try:
        if not args.dry_run:
            controller = Controller(args.serial, args.binary, args.width, args.height)
            controller.start()
            print('ready', flush=True)
        if not args.probe:
            for line in sys.stdin:
                action = validate(json.loads(line), args.width, args.height)
                if controller:
                    controller.action(action)
                print('ok', flush=True)
    finally:
        if controller:
            controller.close()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
