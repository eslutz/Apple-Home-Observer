"""Fixed encrypted Apple Home export. No Keychain, log, recovery-key or plaintext access.

Run through a dedicated source-restricted forced command. The source root is fixed
at deployment; callers cannot choose paths. This module is prepared, not installed.
"""
import io
import json
import os
from pathlib import Path
import re
import stat
import tarfile

ROOT = Path(os.environ.get('OBSERVER_ARCHIVE_ROOT', str(Path.home() / 'Library/Containers/org.example.AppleHomeObserver/Data/Library/Application Support/AppleHomeObserver/archives')))
MAX_FILE = 32 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
UUID = r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'

def private_file(path, maximum, owner):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != owner or before.st_nlink != 1
                or before.st_mode & 0o077 or not 0 < before.st_size <= maximum):
            raise ValueError('unsafe encrypted export source')
        data = stream.read(maximum + 1)
        after = os.fstat(stream.fileno())
        signature = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
        if signature(before) != signature(after) or len(data) != before.st_size:
            raise ValueError('source changed during export')
        return data

def capture(root=ROOT, owner=None):
    owner = os.getuid() if owner is None else owner
    for path in (root, *root.parents):
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, owner) or (info.st_mode & 0o022 and not (info.st_uid == 0 and info.st_mode & stat.S_ISVTX)):
            raise ValueError('unsafe encrypted export ancestry')
    members = {}
    total = 0
    for home in sorted(root.iterdir()):
        info = home.lstat()
        if not re.fullmatch(UUID, home.name) or not stat.S_ISDIR(info.st_mode) or info.st_uid != owner or info.st_mode & 0o077:
            raise ValueError('invalid home export directory')
        index = json.loads(private_file(home / 'index.json', 1024*1024, owner))
        if not isinstance(index,list) or not 1 <= len(index) <= 1024:
            raise ValueError('invalid encrypted export index')
        # Pin a complete generation through its index. Orphan/temp/latest files are not exports.
        names = []
        for item in index:
            if not isinstance(item,dict) or not re.fullmatch(UUID + r'[.]aho',item.get('file','')) or item['file'] in names:
                raise ValueError('invalid encrypted archive name')
            names.append(item['file'])
            data = private_file(home / item['file'], MAX_FILE, owner)
            if not data.startswith(b'AHO1') or len(data) < 33:
                raise ValueError('not an authenticated-format archive')
            total += len(data)
            if total > MAX_TOTAL:
                raise ValueError('encrypted export exceeds budget')
            members[home.name + '/' + item['file']] = data
        # Retention/index publication races reject the generation; next collection retries.
        if json.loads(private_file(home / 'index.json',1024*1024,owner)) != index:
            raise ValueError('archive generation changed')
    if not members or len(members) > 2048:
        raise ValueError('no valid encrypted recovery archives')
    result = io.BytesIO()
    with tarfile.open(fileobj=result,mode='w',format=tarfile.USTAR_FORMAT) as archive:
        for name,data in members.items():
            member = tarfile.TarInfo(name); member.mode = 0o600; member.uid = member.gid = 0; member.uname = member.gname = 'root'; member.size = len(data)
            archive.addfile(member,io.BytesIO(data))
    return result.getvalue()

if __name__ == '__main__':
    import sys
    try:
        if len(sys.argv) != 1:
            raise ValueError('arguments forbidden')
        sys.stdout.buffer.write(capture())
    except Exception:
        print('Encrypted Apple Home export rejected',file=sys.stderr)
        raise SystemExit(1)
