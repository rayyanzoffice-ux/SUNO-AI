import 'package:hive_flutter/hive_flutter.dart';

const _boxIncidents = 'incidents';
const _boxContacts = 'contacts';
const _boxProfile = 'profile';

Future<void> initStorage() async {
  await Hive.initFlutter();
  await Hive.openBox<Map>(_boxIncidents);
  await Hive.openBox<Map>(_boxContacts);
  await Hive.openBox<String>(_boxProfile);
}

Box<Map> get incidentBox => Hive.box<Map>(_boxIncidents);
Box<Map> get contactBox => Hive.box<Map>(_boxContacts);
Box<String> get profileBox => Hive.box<String>(_boxProfile);
