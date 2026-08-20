from pathlib import Path

text = Path('.github/workflows/ios.yml').read_text()
required_fragments = [
    'name: iOS Build',
    'runs-on: macos-14',
    'flutter build ios --release --no-codesign',
    'xcodebuild -workspace ios/Runner.xcworkspace',
    'actions/upload-artifact@v4',
]
missing = [fragment for fragment in required_fragments if fragment not in text]
if missing:
    raise SystemExit(f'Missing workflow fragments: {missing}')
if text.count('${{') != text.count('}}'):
    raise SystemExit('Unbalanced GitHub Actions expression delimiters')
print('GitHub Actions workflow structural checks passed.')
