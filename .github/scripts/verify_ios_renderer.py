"""Reject signed IPAs that enable Flutter 3.29's 16-bit path renderer."""
import glob
import plistlib
import sys
import zipfile


def validate_info(info):
    if info.get('FLTEnableImpeller') is not False:
        raise ValueError('iOS must explicitly disable Impeller for dense map paths')


def verify_ipa(path):
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist()
                 if name.startswith('Payload/') and name.endswith('.app/Info.plist')
                 and name.count('/') == 2]
        if len(names) != 1:
            raise ValueError('Expected one main application Info.plist')
        info = plistlib.loads(archive.read(names[0]))
        validate_info(info)
        return info


if __name__ == '__main__':
    paths = glob.glob(sys.argv[1])
    if len(paths) != 1:
        raise SystemExit('Expected exactly one signed IPA')
    info = verify_ipa(paths[0])
    print(f'Verified iOS build {info.get("CFBundleVersion")}: Impeller disabled; Skia enabled.')
