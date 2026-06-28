import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../widgets/app_header.dart';

class JsaScreen extends StatefulWidget { const JsaScreen({super.key}); @override State<JsaScreen> createState()=>_JsaScreenState(); }
class _JsaScreenState extends State<JsaScreen>{
 String company='Select Company';
 String task='Select Task';
 final sig=SignatureController(penStrokeWidth:3, penColor: Colors.white, exportBackgroundColor: Colors.black);
 final companies=['Select Company','Mach Energy','Continental','Custom'];
 final tasks=['Select Task','Rig up','Flowback','Dump sand','Fixing leaks','Rig down'];
 @override Widget build(BuildContext context)=>Scaffold(appBar: const AppHeader(title:'JSA',showBack:true),body: ListView(padding: const EdgeInsets.all(18),children:[
  DropdownButtonFormField(value:company, items:companies.map((c)=>DropdownMenuItem(value:c,child:Text(c))).toList(), onChanged:(v)=>setState(()=>company=v??companies.first), decoration: const InputDecoration(labelText:'Company')),
  DropdownButtonFormField(value:task, items:tasks.map((c)=>DropdownMenuItem(value:c,child:Text(c))).toList(), onChanged:(v)=>setState(()=>task=v??tasks.first), decoration: const InputDecoration(labelText:'Task')),
  const Text('Recommendations', style: TextStyle(color: Color(0xFFCDA56A),fontWeight:FontWeight.bold)),
  const Text('Stand in safe position. Isolate and bleed off PSI when needed.'),
  const SizedBox(height:16),
  const Text('Employee Signatures', style: TextStyle(color: Color(0xFFCDA56A),fontWeight:FontWeight.bold)),
  for(int i=1;i<=6;i++) TextField(decoration: InputDecoration(labelText:'Employee $i Name / Company')),
  const SizedBox(height:16),
  Container(height:180, decoration: BoxDecoration(border:Border.all(color:Colors.white24), borderRadius:BorderRadius.circular(12)), child: Signature(controller:sig, backgroundColor: const Color(0xFF111111))),
  Row(children:[Expanded(child:OutlinedButton(onPressed:()=>sig.clear(), child: const Text('Clear Signature'))), const SizedBox(width:10), Expanded(child:FilledButton(onPressed:(){}, child: const Text('Save JSA')))]),
 ]));
}
