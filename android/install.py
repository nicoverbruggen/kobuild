#!/usr/bin/env python3
"""Install the checksum-pinned Android tools and Qt kits from official archives."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


def download(spec, destination):
    if destination.is_file():
        with destination.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() == spec['sha256']:
                return
    partial = destination.with_name(destination.name + '.partial')
    print('Downloading ' + spec['name'], flush=True)
    subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location', '--retry', '3',
                    '--connect-timeout', '30', '--output', str(partial), spec['url']], check=True)
    with partial.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != spec['sha256']:
            raise ValueError('Download checksum mismatch: ' + spec['name'])
    partial.replace(destination)


def main():
    manifest_path = Path(__file__).with_name('manifest.json')
    manifest = json.loads(manifest_path.read_text())
    sdk = Path(os.environ['ANDROID_HOME'])
    sources = Path('/usr/src/kobuild/android')
    sources.mkdir(parents=True, exist_ok=True)
    docs = Path('/usr/share/doc/kobuild')
    docs.mkdir(parents=True, exist_ok=True)
    shutil.copy2(manifest_path, docs / 'android-manifest.json')
    cache = Path('/var/cache/kobuild-android')
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='kobuild-install-') as temporary:
        work = Path(temporary)
        for spec in manifest['qt_archives']:
            archive = cache / spec['name']
            download(spec, archive)
            if spec['kind'] == 'source':
                shutil.copy2(archive, sources / archive.name)
                if spec['name'].startswith('qtbase-'):
                    with tarfile.open(archive) as source:
                        for member in source.getmembers():
                            if member.isfile() and 'LICENSES' in Path(member.name).parts:
                                licenses = docs / 'qt-licenses'
                                licenses.mkdir(exist_ok=True)
                                with source.extractfile(member) as stream:
                                    (licenses / Path(member.name).name).write_bytes(stream.read())
            else:
                prefix = Path(os.environ[spec['destination']]) / spec.get('subdirectory', '')
                subprocess.run(['7z', 'x', '-y', '-bso0', '-o' + str(prefix), str(archive)], check=True)
        spec = manifest['command_line_tools']
        archive = cache / spec['name']
        download(spec, archive)
        with zipfile.ZipFile(archive) as tools:
            tools.extractall(work / 'command-line-tools')
        target = sdk / 'cmdline-tools/pinned'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(work / 'command-line-tools/cmdline-tools'), target)
        # zipfile does not preserve executable permission bits.
        for tool in (target / 'bin').iterdir():
            tool.chmod(0o755)
    # Qt's kits relocate through qt.conf. Use the installed Linux tools for
    # Android code generation, rather than tools from the kit's build machine.
    for name in ('QT_HOST_PATH', 'QT_ANDROID_ARM64_PATH'):
        prefix = Path(os.environ[name])
        (prefix / 'bin/qt.conf').write_text('[Paths]\nPrefix=..\n')
    sdkmanager = str(sdk / 'cmdline-tools/pinned/bin/sdkmanager')
    with subprocess.Popen(['yes'], stdout=subprocess.PIPE) as answers:
        try:
            subprocess.run([sdkmanager, '--sdk_root=' + str(sdk), *manifest['sdk_packages']],
                           stdin=answers.stdout, check=True)
        finally:
            answers.stdout.close()
            answers.terminate()
            answers.wait()
    with (docs / 'android-packages.txt').open('w') as record:
        subprocess.run([sdkmanager, '--sdk_root=' + str(sdk), '--list_installed'], stdout=record, check=True)


if __name__ == '__main__':
    main()
