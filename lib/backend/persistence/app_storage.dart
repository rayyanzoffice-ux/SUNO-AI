import 'package:hive_flutter/hive_flutter.dart';

const _boxIncidents = 'incidents';
const _boxContacts = 'contacts';

Future<void> initStorage() async {
  await Hive.initFlutter();
  await Hive.openBox<Map>(_boxIncidents);
  await Hive.openBox<Map>(_boxContacts);
}

Box<Map> get incidentBox => Hive.box<Map>(_boxIncidents);
Box<Map> get contactBox => Hive.box<Map>(_boxContacts);
