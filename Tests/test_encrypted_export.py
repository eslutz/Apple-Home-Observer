import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
import uuid
import importlib.util
spec=importlib.util.spec_from_file_location("encrypted_export",Path(__file__).resolve().parents[1]/"script/encrypted_export.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
capture=module.capture
class ExportTests(unittest.TestCase):
    def source(self,root):
        home=root/str(uuid.uuid4());home.mkdir(mode=0o700)
        file=home/(str(uuid.uuid4())+'.aho');file.write_bytes(b'AHO1'+b'x'*50);file.chmod(0o600)
        index=home/'index.json';index.write_text(json.dumps([dict(file=file.name)]));index.chmod(0o600)
        return home,file
    def test_exports_ciphertext_only(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as d:
            root=Path(d);home,file=self.source(root)
            (home/'private.recovery-key').write_text('do-not-export')
            payload=capture(root)
            with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
                self.assertEqual(archive.getnames(),[home.name+'/'+file.name])
                self.assertEqual(archive.extractfile(archive.getmembers()[0]).read(),file.read_bytes())
            self.assertNotIn(b'do-not-export',payload)
    def test_symlink_and_plaintext_rejected(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as d:
            root=Path(d);_,file=self.source(root)
            file.write_bytes(b'plaintext'*10);self.assertRaises(ValueError,capture,root)
            target=root/'secret';target.write_bytes(b'AHO1'+b'x'*50);target.chmod(0o600);file.unlink();file.symlink_to(target)
            self.assertRaises((OSError,ValueError),capture,root)
    def test_unsafe_index_path_and_public_permissions_rejected(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as d:
            root=Path(d);home,file=self.source(root)
            file.chmod(0o644);self.assertRaises(ValueError,capture,root)
            file.chmod(0o600);(home/'index.json').write_text(json.dumps([dict(file='../secret.aho')]))
            self.assertRaises(ValueError,capture,root)
