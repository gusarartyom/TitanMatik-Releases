import copy
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import github_release as gh

class FakeGitHub:
    repo = 'owner/TitanMatik-Releases'
    def __init__(self):
        self.releases = {}
        self.data = {}
        self.current_id = None
        self.corrupt_upload = False
        self.public_bad = False
        self.private = False
        self.promotions = 0
        self.public_checks = 0
    def assert_public(self):
        if self.private: raise ValueError('Private repo forbidden')
    def latest(self): return copy.deepcopy(self.releases.get(self.current_id))
    def by_tag(self, tag):
        return copy.deepcopy(next((r for r in self.releases.values() if r['tag_name']==tag),None))
    def create(self, tag, body):
        number = len(self.releases)+1
        release = dict(id=number,tag_name=tag,body=body,draft=True,prerelease=True,assets=[])
        self.releases[number]=release
        return copy.deepcopy(release)
    def upload(self, release, name, data):
        number=len(self.data)+1
        self.data[number]=b'corrupted' if self.corrupt_upload and name==gh.SETUP else data
        self.releases[release['id']]['assets'].append(dict(id=number,name=name,size=len(data)))
    def read_asset(self, asset): return io.BytesIO(self.data[asset['id']])
    def patch(self, release, **fields):
        if fields.get('make_latest')=='true':
            self.current_id=release['id']; self.promotions+=1
        self.releases[release['id']].update(fields)
        return copy.deepcopy(self.releases[release['id']])
    def verify_public(self, release, digest):
        self.public_checks+=1
        if self.public_bad: raise ValueError('Anonymous download corruption')

class GitHubReleaseTests(unittest.TestCase):
    def setUp(self):
        scratch=Path.cwd()/'.test-temp'; scratch.mkdir(exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.setup=Path(self.temp.name)/'setup.exe'; self.setup.write_bytes(b'tested setup')
        self.manifest={'source_sha256':'a'*64,'files':[]}
        self.api=FakeGitHub()
        self.env=patch.dict(os.environ,{'RUN_URL':'https://github.com/test/run',
                                      'PRODUCTION_ENABLED':'true','UPDATE_CHANNEL_ID':'@test'})
        self.env.start(); self.addCleanup(self.env.stop)
    def prepare(self, mode='stage'):
        return gh.prepare(self.api,self.manifest,self.setup,mode)
    def test_candidate_remains_draft(self):
        release=self.prepare('candidate')
        self.assertTrue(release['draft']); self.assertIsNone(self.api.latest())
        self.assertEqual(self.api.public_checks,0)
    def test_unpublished_draft_found_when_tag_endpoint_returns_404(self):
        api=gh.GitHub('owner/repo','test-token')
        tag='tm-'+'a'*64+'-'+'b'*64
        draft={'id':7,'tag_name':tag,'draft':True}
        with patch.object(api,'optional',return_value=None), patch.object(api,'request',return_value=[draft]):
            self.assertEqual(api.by_tag(tag),draft)
    def test_duplicate_draft_identity_is_rejected(self):
        api=gh.GitHub('owner/repo','test-token')
        tag='tm-'+'a'*64+'-'+'b'*64
        with patch.object(api,'optional',return_value=None), patch.object(api,'request',return_value=[{'tag_name':tag},{'tag_name':tag}]):
            with self.assertRaises(ValueError): api.by_tag(tag)
    def test_stage_keeps_latest_unchanged(self):
        release=self.prepare()
        self.assertFalse(release['draft']); self.assertTrue(release['prerelease'])
        self.assertIsNone(self.api.latest()); self.assertEqual(self.api.public_checks,1)
    def test_corrupt_upload_never_publishes(self):
        self.api.corrupt_upload=True
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue(self.api.releases[1]['draft'])
        self.assertIsNone(self.api.latest())
    def test_bad_public_download_never_switches_latest(self):
        self.api.public_bad=True
        with self.assertRaises(ValueError): self.prepare()
        self.assertIsNone(self.api.latest())
    def test_promotion_requires_staged_release(self):
        release=self.prepare('candidate')
        with self.assertRaises(ValueError): gh.promote(self.api,release['tag_name'])
        self.assertEqual(self.api.promotions,0)
    def test_promotion_requires_gate(self):
        release=self.prepare()
        with patch.dict(os.environ,{'PRODUCTION_ENABLED':'false'}), self.assertRaises(ValueError):
            gh.promote(self.api,release['tag_name'])
        self.assertEqual(self.api.promotions,0)
    def test_promotion_verifies_public_download_first(self):
        release=self.prepare(); self.api.public_bad=True
        with self.assertRaises(ValueError): gh.promote(self.api,release['tag_name'])
        self.assertEqual(self.api.promotions,0)
    def test_promotion_preserves_previous_release(self):
        first=self.prepare(); gh.promote(self.api,first['tag_name'])
        self.manifest={'source_sha256':'b'*64,'files':[]}
        second=self.prepare(); gh.promote(self.api,second['tag_name'])
        self.assertEqual(self.api.latest()['id'],second['id'])
        self.assertIn(first['tag_name'],self.api.latest()['body'])
        self.assertIn(first['id'],self.api.releases)
    def test_candidate_cannot_announce(self):
        release=self.prepare('candidate')
        with patch('github_release.send_message') as send, self.assertRaises(ValueError):
            gh.announce(self.api,release)
        send.assert_not_called()
    def test_notification_uses_latest_state_and_sends_once(self):
        release=gh.promote(self.api,self.prepare()['tag_name'])
        with patch('github_release.send_message',return_value=123) as send:
            gh.announce(self.api,release); gh.announce(self.api,release)
        self.assertEqual(send.call_count,1)
    def test_uncertain_telegram_delivery_never_repeats(self):
        release=gh.promote(self.api,self.prepare()['tag_name'])
        with patch('github_release.send_message',side_effect=TimeoutError) as send:
            with self.assertRaises(TimeoutError): gh.announce(self.api,release)
            with self.assertRaises(ValueError): gh.announce(self.api,release)
        self.assertEqual(send.call_count,1)
    def test_resume_draft_does_not_replace_assets(self):
        release=self.prepare('candidate'); original=copy.deepcopy(self.api.data)
        self.prepare('candidate')
        self.assertEqual(original,self.api.data)
    def test_private_repository_is_rejected(self):
        self.api.private=True
        with self.assertRaises(ValueError): self.prepare()
        self.assertEqual(self.api.releases,{})
    def test_asset_redirect_does_not_forward_token(self):
        api=gh.GitHub('owner/repo','test-token')
        redirect=urllib.error.HTTPError('https://api.github.com',302,'redirect',
            {'Location':'https://release-assets.githubusercontent.com/asset'},None)
        with patch.object(api.opener,'open',side_effect=[redirect,io.BytesIO(b'asset')]) as opener:
            with api.read_asset({'id':1}) as response: self.assertEqual(response.read(),b'asset')
        self.assertEqual(opener.call_args_list[0].args[0].get_header('Authorization'),'Bearer test-token')
        self.assertIsNone(opener.call_args_list[1].args[0].get_header('Authorization'))
    def test_unexpected_asset_redirect_is_rejected(self):
        api=gh.GitHub('owner/repo','test-token')
        redirect=urllib.error.HTTPError('https://api.github.com',302,'redirect',
            {'Location':'https://untrusted.invalid/asset'},None)
        with patch.object(api.opener,'open',side_effect=redirect) as opener, self.assertRaises(ValueError):
            api.read_asset({'id':1})
        self.assertEqual(opener.call_count,1)

if __name__=='__main__': unittest.main()
