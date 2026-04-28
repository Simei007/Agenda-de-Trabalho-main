const String defaultApkInstallUrl =
    'https://github.com/Simei007/Agenda-de-Trabalho/releases/latest/download/app-release.apk';

const int normalWorkMinutes = 7 * 60 + 20;
const int nightStartMinutes = 22 * 60;
const int nightEndMinutes = 5 * 60;

const Duration ctbRefreshInterval = Duration(hours: 24);

final DateTime firstAllowedDay = DateTime(2020, 1, 1);
final DateTime lastAllowedDay = DateTime(2030, 12, 31);
