$env:PUB_CACHE = 'D:\flutter-cache'
$env:TEMP = 'D:\flutter-temp'
$env:TMP = 'D:\flutter-temp'
$env:HTTP_PROXY = $null
$env:HTTPS_PROXY = $null
$env:ALL_PROXY = $null
$env:NO_PROXY = 'pub.dev,.pub.dev,storage.googleapis.com'
& 'D:\tools\flutter_windows_3.47.5-stable\flutter\bin\flutter.bat' build apk --release *>> 'D:\codex_program\infinite_paper\build_release_1_2.log'

