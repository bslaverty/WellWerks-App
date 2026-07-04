import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

class EquipmentScreen extends StatefulWidget { const EquipmentScreen({super.key}); @override State<EquipmentScreen> createState()=>_EquipmentScreenState(); }
class _EquipmentScreenState extends State<EquipmentScreen>{
 final items=['Sand Separator #1','Sand Separator #2','Plug Catcher','Choke Manifold','Line Heater','Test Unit','ECD','VRU'];
 final statuses=<String,String>{};
 @override Widget build(BuildContext context)=>Scaffold(appBar: const AppHeader(title:'Equipment Status',showBack:true),body: ListView(padding: const EdgeInsets.all(18),children: items.map((e){final s=statuses[e]??'Online'; return Card(child: ListTile(title: Text(e), subtitle: Text(s), trailing: DropdownButton<String>(value:s, items:['Online','Bypassed','Standby','Maintenance','Offline','Plugged','Isolated'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(), onChanged:(v)=>setState(()=>statuses[e]=v??'Online'))));}).toList()));
}
