"""Real Windows compiler regression for player folders with Unicode and spaces."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import build_game


@unittest.skipUnless(os.name == 'nt', 'Windows player compiler regression')
class UnicodePchTests(unittest.TestCase):
    def test_player_flags_build_cmake_pch_with_absolute_unicode_include(self):
        vswhere = Path(os.environ.get('PROGRAMFILES(X86)', r'C:\Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
        if not vswhere.is_file():
            self.skipTest('Visual Studio Build Tools are not installed')
        with tempfile.TemporaryDirectory(prefix='t4 player Unicode Tëst ') as folder:
            root = Path(folder)
            args = build_game.parser().parse_args(['-Steps', 'prereq', '-LogDir', str(root / 'logs')])
            build = build_game.Build(args, root=root)
            try:
                build.compiler_environment()
            finally:
                build.log.close()
            cmake = shutil.which('cmake', path=build.env.get('PATH'))
            ninja = shutil.which('ninja', path=build.env.get('PATH'))
            if not cmake or not ninja:
                self.skipTest('CMake and Ninja are not installed')
            (root / 'héader.hpp').write_text('inline constexpr unsigned kUnicodePathValue = 123u;\n', encoding='utf-8')
            (root / 'probe.cpp').write_text('unsigned player_path_probe() { return kUnicodePathValue; }\n', encoding='utf-8')
            (root / 'CMakeLists.txt').write_text(
                'cmake_minimum_required(VERSION 3.20)\n'
                'project(player_unicode_pch LANGUAGES CXX)\n'
                'set(CMAKE_CXX_STANDARD 20)\n'
                'add_library(probe STATIC probe.cpp)\n'
                'target_precompile_headers(probe PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/héader.hpp")\n',
                encoding='utf-8')
            plan = build_game.cmake_plan(root, root, 'runtime', True, False, {})[0]
            flags = [arg for arg in plan if arg.startswith('-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=')]
            self.assertEqual(len(flags), 1)
            environment = dict(build.env)
            environment.pop('CL', None)
            environment.pop('_CL_', None)
            commands = [[cmake, '-S', str(root), '-B', str(root / 'out'), '-G', 'Ninja',
                         '-DCMAKE_BUILD_TYPE=RelWithDebInfo', *flags],
                        [cmake, '--build', str(root / 'out'), '--target', 'probe']]
            for command in commands:
                result = subprocess.run(command, env=environment, capture_output=True, text=True,
                                        encoding='utf-8', errors='replace',
                                        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((root / 'out/probe.lib').is_file())
            self.assertTrue(list((root / 'out').rglob('*.pch')), 'The regression must compile a real PCH')


if __name__ == '__main__':
    unittest.main()
