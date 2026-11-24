#!/usr/bin/env python3
"""Host-side input validation and cleanup tests; no Android events are sent."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
import sys
sys.dont_write_bytecode = True
from unittest.mock import Mock

SCRIPT = Path(__file__).resolve().parents[1] / '.agents/skills/android-home-organizer/scripts/control.py'
spec = importlib.util.spec_from_file_location('home_control', SCRIPT)
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


class HomeOrganizerTests(unittest.TestCase):
    def test_bounds_and_non_finite_values(self):
        for value in [-1, 100, float('nan'), float('inf'), True, '2']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                control.validate({'op': 'tap', 'x': value, 'y': 1}, 100, 200)
        control.validate({'op': 'tap', 'x': 99, 'y': 199}, 100, 200)

    def test_no_unknown_or_partial_actions(self):
        for action in [[], {}, {'op': 'tap', 'x': 1},
                       {'op': 'tap', 'x': 1, 'y': 1, 'extra': 1},
                       {'op': 'key', 'usage': 40}]:
            with self.subTest(action=action), self.assertRaises(ValueError):
                control.validate(action, 100, 200)

    def test_unsupported_text_rejected_before_typing(self):
        for value in ['Tools\n', 'Tools!', '\u03a9', '', 'a' * 81]:
            with self.subTest(value=repr(value)), self.assertRaises(ValueError):
                control.validate({'op': 'text', 'value': value,
                                  'package': 'launcher', 'resource': 'title'}, 100, 200)

    def test_missing_editor_never_sends_keys(self):
        c = control.Controller('selected-device', __file__, 100, 200)
        c.remote = '/data/local/tmp/test'
        c.check_display = Mock()
        c.adb_run = Mock(return_value='<hierarchy/>')
        c.key = Mock()
        with self.assertRaises(RuntimeError):
            c.action({'op': 'text', 'value': 'Tools', 'package': 'launcher', 'resource': 'title'})
        c.key.assert_not_called()

    def test_focus_requires_matching_non_password_editor(self):
        attrs = dict(package='launcher', **{'resource-id': 'title', 'class': 'android.widget.EditText',
                                           'focused': 'true', 'enabled': 'true', 'password': 'false'})
        def xml(a):
            return '<hierarchy><node ' + ' '.join(f'{k}="{v}"' for k, v in a.items()) + '/></hierarchy>'
        self.assertTrue(control.focused_editor(xml(attrs), 'launcher', 'title'))
        for key, val in [('focused', 'false'), ('enabled', 'false'), ('password', 'true'),
                         ('class', 'android.widget.TextView'), ('package', 'another-app')]:
            self.assertFalse(control.focused_editor(xml(dict(attrs, **{key: val})), 'launcher', 'title'))

    def test_display_changes_are_rejected(self):
        c = control.Controller('selected-device', __file__, 100, 200)
        good = 'Viewport INTERNAL: orientation=0, logicalFrame=[0, 0, 100, 200], isActive=[1]'
        c.check_display(good)
        for state in [good.replace('orientation=0', 'orientation=1'),
                      good.replace('100, 200', '200, 100'), good.replace('[1]', '[0]')]:
            with self.assertRaises(RuntimeError):
                c.check_display(state)

    def test_touch_is_released_after_drag_failure(self):
        c = control.Controller('selected-device', __file__, 100, 200)
        c.check_display = Mock()
        calls = []
        def touch(down, x, y):
            calls.append((down, x, y))
            if down and len(calls) > 1:
                raise RuntimeError('connection interrupted')
        c.touch = touch
        with self.assertRaises(RuntimeError):
            c.action({'op': 'drag', 'x': 1, 'y': 1, 'to_x': 50, 'to_y': 50, 'hold': 0})
        self.assertEqual(calls[-1][0], 0)

    def test_close_ends_stream_and_removes_only_session_directory(self):
        c = control.Controller('selected-device', __file__, 100, 200)
        c.remote = '/data/local/tmp/home-organizer.test'
        c.process, c.adb_run = Mock(), Mock()
        c.close()
        c.process.stdin.close.assert_called_once()
        c.process.wait.assert_called_once_with(timeout=5)
        c.adb_run.assert_called_once_with('shell', 'rm', '-rf', c.remote)

    def test_dry_run_without_adb_or_binary(self):
        import sys
        result = subprocess.run([sys.executable, str(SCRIPT), '--dry-run', '--width', '100', '--height', '200'],
                                input='{"op":"tap","x":1,"y":2}\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'ok')


if __name__ == '__main__':
    unittest.main()
