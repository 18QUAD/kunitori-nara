import importlib.util
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / '.github/scripts/testflight_config.py'
spec = importlib.util.spec_from_file_location('testflight_config', SCRIPT)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class TestFlightConfigurationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rsa = subprocess.check_output(['openssl', 'genpkey', '-algorithm', 'RSA',
                                          '-pkeyopt', 'rsa_keygen_bits:2048'], stderr=subprocess.DEVNULL, text=True)
        cls.ec = subprocess.check_output(['openssl', 'genpkey', '-algorithm', 'EC',
                                         '-pkeyopt', 'ec_paramgen_curve:P-256'], text=True)

    def credentials(self):
        return {'ASC_KEY_ID': 'ABCDE12345',
                'ASC_ISSUER_ID': 'bb01c986-ea78-48bc-810f-e8fe98dc4def',
                'ASC_PRIVATE_KEY': self.ec,
                'IOS_CERTIFICATE_PRIVATE_KEY': self.rsa,
                'ASC_APP_ID': '1234567890'}

    def test_missing_credentials_are_named_without_values(self):
        errors = config.validate({})
        self.assertEqual(len(errors), len(config.REQUIRED))
        self.assertTrue(all('not configured' in error for error in errors))

    def test_valid_signing_and_api_keys(self):
        self.assertEqual(config.validate(self.credentials()), [])

    def test_swapped_keys_are_rejected_without_logging_secrets(self):
        env = self.credentials()
        env['ASC_PRIVATE_KEY'], env['IOS_CERTIFICATE_PRIVATE_KEY'] = env['IOS_CERTIFICATE_PRIVATE_KEY'], env['ASC_PRIVATE_KEY']
        errors = '\n'.join(config.validate(env))
        self.assertIn('ASC_PRIVATE_KEY:', errors)
        self.assertIn('IOS_CERTIFICATE_PRIVATE_KEY:', errors)
        self.assertNotIn('BEGIN', errors)
        self.assertNotIn(self.rsa, errors)

    def test_invalid_identifiers_are_rejected_without_echoing_them(self):
        env = self.credentials()
        env.update(ASC_KEY_ID='bad key id', ASC_ISSUER_ID='private-issuer-value', ASC_APP_ID='io.github.quad18.kunitori')
        errors = '\n'.join(config.validate(env))
        self.assertIn('ASC_APP_ID:', errors)
        self.assertNotIn('private-issuer-value', errors)

    def test_build_numbers_increment_and_carry(self):
        for old, new in [('', '1'), ('null', '1'), ('None', '1'), ('1', '2'),
                         ('123', '124'), ('2.5', '2.6'), ('2.99', '3.0'),
                         ('2.99.99', '3.0.0')]:
            with self.subTest(old=old):
                self.assertEqual(config.next_build_number(old), new)

    def test_invalid_api_response_never_silently_reuses_a_number(self):
        for value in ['permission denied', '0.1.100', '1.2.3.4', '9999', '9999.99.99']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                config.next_build_number(value)


if __name__ == '__main__':
    unittest.main()
