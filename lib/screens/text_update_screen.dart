import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_header.dart';

class TextUpdateScreen extends StatefulWidget {
  const TextUpdateScreen({super.key});

  @override
  State<TextUpdateScreen> createState() => _TextUpdateScreenState();
}

class _TextUpdateScreenState extends State<TextUpdateScreen> {
  final padName = TextEditingController(text: '');
  final customCompanyName = TextEditingController(text: '');
  final List<WellUpdate> wells = [WellUpdate(name: 'Well 1')];
  final Map<String, SavedTemplate> savedTemplates = {};

  String selectedTime = '9:00 AM';
  String selectedTemplate = 'Continental Resources';

  final List<String> times = const [
    '12:00 AM', '1:00 AM', '2:00 AM', '3:00 AM', '4:00 AM', '5:00 AM',
    '6:00 AM', '7:00 AM', '8:00 AM', '9:00 AM', '10:00 AM', '11:00 AM',
    '12:00 PM', '1:00 PM', '2:00 PM', '3:00 PM', '4:00 PM', '5:00 PM',
    '6:00 PM', '7:00 PM', '8:00 PM', '9:00 PM', '10:00 PM', '11:00 PM',
  ];

  String get companyName {
    if (selectedTemplate == 'Mach') return 'Mach Resources';
    if (selectedTemplate == 'Continental Resources') return 'Continental Resources';
    if (selectedTemplate == 'Custom') return customCompanyName.text.trim().isEmpty ? 'Custom Company' : customCompanyName.text.trim();
    return selectedTemplate;
  }

  bool get isContinental => selectedTemplate == 'Continental Resources' || savedTemplates[selectedTemplate]?.base == 'Continental Resources';
  bool get isMach => selectedTemplate == 'Mach' || savedTemplates[selectedTemplate]?.base == 'Mach';

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    padName.dispose();
    customCompanyName.dispose();
    for (final w in wells) {
      w.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('text_update_templates') ?? [];
    final loaded = <String, SavedTemplate>{};
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final template = SavedTemplate.fromJson(map);
        loaded[template.name] = template;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => savedTemplates.addAll(loaded));
  }

  Future<void> _saveCustomTemplate() async {
    final name = customCompanyName.text.trim();
    if (name.isEmpty) {
      _snack('Enter a company name first.');
      return;
    }
    final template = SavedTemplate(
      name: name,
      base: isMach ? 'Mach' : 'Continental Resources',
      include: Map<String, bool>.from(wells.first.include),
    );
    savedTemplates[name] = template;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'text_update_templates',
      savedTemplates.values.map((t) => jsonEncode(t.toJson())).toList(),
    );
    if (!mounted) return;
    setState(() => selectedTemplate = name);
    _snack('$name saved to templates.');
  }

  void _applyTemplate(String value) {
    setState(() {
      selectedTemplate = value;
      if (value == 'Continental Resources') {
        for (final w in wells) {
          w.applyContinental();
        }
      } else if (value == 'Mach') {
        for (final w in wells) {
          w.applyMach();
        }
      } else if (value == 'Custom') {
        customCompanyName.clear();
      } else if (savedTemplates.containsKey(value)) {
        final t = savedTemplates[value]!;
        customCompanyName.text = t.name;
        for (final w in wells) {
          w.include
            ..clear()
            ..addAll(t.include);
        }
      }
    });
  }

  void _addWell() {
    setState(() => wells.add(WellUpdate(name: 'Well ${wells.length + 1}')..copyIncludesFrom(wells.first)));
  }

  void _duplicateWell(int index) {
    setState(() => wells.insert(index + 1, wells[index].duplicate('${wells[index].wellName.text} Copy')));
  }

  void _removeWell(int index) {
    if (wells.length == 1) {
      _snack('At least one well is required.');
      return;
    }
    setState(() => wells.removeAt(index).dispose());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _v(TextEditingController c) => c.text.trim();

  String get updateText {
    final lines = <String>[];
    lines.add('$selectedTime UPDATE');
    if (companyName.trim().isNotEmpty) lines.add('Company: ${companyName.trim()}');
    if (_v(padName).isNotEmpty) lines.add('Pad: ${_v(padName)}');
    lines.add('');

    for (var i = 0; i < wells.length; i++) {
      final well = wells[i];
      final name = _v(well.wellName).isEmpty ? 'Well ${i + 1}' : _v(well.wellName);
      lines.add('------------------------------');
      lines.add('WELL: $name');
      lines.add('------------------------------');

      if (isMach) {
        _appendMach(lines, well);
      } else {
        _appendContinental(lines, well);
      }

      if (well.on('notes') && _v(well.notes).isNotEmpty) {
        lines.add('');
        lines.add(_v(well.notes));
      }
      if (i != wells.length - 1) lines.add('');
    }
    return lines.join('\n');
  }

  void _appendMach(List<String> lines, WellUpdate w) {
    if (w.on('choke') && _v(w.choke).isNotEmpty) lines.add('Choke ${_v(w.choke)} ${w.chokeType}');
    if (w.on('csg') && _v(w.csg).isNotEmpty) lines.add('Csg ${_v(w.csg)}');
    if (w.on('bwph') && _v(w.bwph).isNotEmpty) lines.add('Wtr/hr ${_v(w.bwph)}');
    if (w.on('boph') && _v(w.boph).isNotEmpty) lines.add('Oil/hr ${_v(w.boph)}');
    if (w.on('gas24') && _v(w.gas24).isNotEmpty) lines.add('${_v(w.gas24)} 24/hr gas rate');
    if (w.on('sand') && _v(w.sand).isNotEmpty) lines.add('Sand ${_v(w.sand)} gal/hr');
  }

  void _appendContinental(List<String> lines, WellUpdate w) {
    if (w.on('csg') && _v(w.csg).isNotEmpty) lines.add('CSG - ${_v(w.csg)} PSI');
    if (w.on('icp') && _v(w.icp).isNotEmpty) lines.add('ICP - ${_v(w.icp)} PSI');
    if (w.on('choke') && _v(w.choke).isNotEmpty) lines.add('CHK - ${_v(w.choke)} ${w.chokeType}');
    if (w.on('bwph') && _v(w.bwph).isNotEmpty) lines.add('BWPH - ${_v(w.bwph)}');
    if (w.on('boph') && _v(w.boph).isNotEmpty) lines.add('BOPH - ${_v(w.boph)}');
    if (w.on('gasSpot') && _v(w.gasSpot).isNotEmpty) lines.add('GAS SPOT RT. ${_v(w.gasSpot)} MMCF/d');
    if (w.on('gas24') && _v(w.gas24).isNotEmpty) lines.add('24HR GAS RT - ${_v(w.gas24)} MCF');
    if (w.on('diff') && _v(w.diff).isNotEmpty) lines.add('DIFF - ${_v(w.diff)}');
    if (w.on('stat') && _v(w.stat).isNotEmpty) lines.add('STAT - ${_v(w.stat)}');
    if (w.on('temp') && _v(w.temp).isNotEmpty) lines.add('TEMP - ${_v(w.temp)}°');
    if (w.on('prop') && _v(w.prop).isNotEmpty) lines.add('PROP - ${_v(w.prop)} GPH');
    if (w.on('h2oSg') && _v(w.h2oSg).isNotEmpty) lines.add('H2O SG - ${_v(w.h2oSg)}');
    if (w.on('wht') && _v(w.wht).isNotEmpty) lines.add('WHT - ${_v(w.wht)}°');
    if (w.on('wtrTmp') && _v(w.wtrTmp).isNotEmpty) lines.add('WTR TMP - ${_v(w.wtrTmp)}°');
    if (w.on('flareRate') && _v(w.flareRate).isNotEmpty) lines.add('FLARE RT - ${_v(w.flareRate)} MCF/d');
    if (w.on('flarePilotTemp') && _v(w.flarePilotTemp).isNotEmpty) lines.add('FLARE PILOT TEMP - ${_v(w.flarePilotTemp)}°');
    if (w.on('biocide') && _v(w.biocide).isNotEmpty) lines.add('BIOCIDE - ${_v(w.biocide)} GPD');
    if (w.on('sand') && _v(w.sand).isNotEmpty) lines.add('SAND - ${_v(w.sand)} GAL/hr');

    if (w.on('vru') && (_v(w.vruGas).isNotEmpty || _v(w.vruSuction).isNotEmpty || _v(w.vruDischarge).isNotEmpty)) {
      lines.add('');
      lines.add('VRU');
      if (_v(w.vruGas).isNotEmpty) lines.add('GAS RT - ${_v(w.vruGas)} MCF/d');
      if (_v(w.vruSuction).isNotEmpty) lines.add('SUCTION - ${_v(w.vruSuction)} PSI');
      if (_v(w.vruDischarge).isNotEmpty) lines.add('DISCHARGE - ${_v(w.vruDischarge)} PSI');
    }

    if (w.on('compressor') && (_v(w.compressorCompany).isNotEmpty || _v(w.compressorSuction).isNotEmpty || _v(w.compressorDischarge).isNotEmpty || _v(w.injectionRate).isNotEmpty)) {
      lines.add('');
      if (_v(w.compressorCompany).isNotEmpty) {
        lines.add('COMPRESSOR - ${_v(w.compressorCompany)}');
      } else {
        lines.add('COMPRESSOR');
      }
      if (_v(w.compressorSuction).isNotEmpty) lines.add('SUCTION - ${_v(w.compressorSuction)} PSI');
      if (_v(w.compressorDischarge).isNotEmpty) lines.add('DISCHARGE - ${_v(w.compressorDischarge)} PSI');
      if (_v(w.injectionRate).isNotEmpty) lines.add('INJECTION RATE - ${_v(w.injectionRate)} MCF');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: updateText));
    _snack('Text update copied');
  }

  Widget _companyPicker() {
    final items = <String>['Continental Resources', 'Mach', ...savedTemplates.keys, 'Custom'];
    return DropdownButtonFormField<String>(
      value: items.contains(selectedTemplate) ? selectedTemplate : 'Continental Resources',
      decoration: const InputDecoration(labelText: 'Company Template'),
      items: items.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
      onChanged: (value) => _applyTemplate(value ?? 'Continental Resources'),
    );
  }

  Widget _check(WellUpdate w, String key, String label) {
    return CheckboxListTile(
      value: w.on(key),
      onChanged: (value) => setState(() => w.include[key] = value ?? false),
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _field(String label, TextEditingController controller, {String? suffix, TextInputType? keyboardType, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType ?? (lines > 1 ? TextInputType.multiline : const TextInputType.numberWithOptions(decimal: true)),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  Widget _wellCard(int index) {
    final w = wells[index];
    return _section('Well ${index + 1}', [
      Row(
        children: [
          Expanded(child: _field('Well Name', w.wellName, keyboardType: TextInputType.text)),
          IconButton(onPressed: () => _duplicateWell(index), icon: const Icon(Icons.copy)),
          IconButton(onPressed: () => _removeWell(index), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      const Divider(),
      ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Fields to include'),
        children: [
          _check(w, 'csg', 'CSG'),
          _check(w, 'icp', 'ICP'),
          _check(w, 'choke', 'Choke POS / ADJ'),
          _check(w, 'bwph', isMach ? 'Water/hr' : 'BWPH'),
          _check(w, 'boph', isMach ? 'Oil/hr' : 'BOPH'),
          _check(w, 'gasSpot', 'Gas Spot Rate'),
          _check(w, 'gas24', '24hr Gas Rate'),
          _check(w, 'sand', 'Sand GAL/hr'),
          _check(w, 'diff', 'Diff'),
          _check(w, 'stat', 'Stat'),
          _check(w, 'temp', 'Temp'),
          _check(w, 'prop', 'Prop GPH'),
          _check(w, 'h2oSg', 'H2O SG'),
          _check(w, 'wht', 'WHT'),
          _check(w, 'wtrTmp', 'WTR TMP'),
          _check(w, 'flareRate', 'Flare Rate'),
          _check(w, 'flarePilotTemp', 'Flare Pilot Temp'),
          _check(w, 'biocide', 'Biocide'),
          _check(w, 'vru', 'VRU Section'),
          _check(w, 'compressor', 'Compressor Section'),
          _check(w, 'notes', 'Notes'),
        ],
      ),
      const Divider(),
      _field('CSG', w.csg, suffix: 'PSI'),
      _field('ICP', w.icp, suffix: 'PSI'),
      const SizedBox(height: 4),
      const Text('Choke Type', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'POS', label: Text('POS')),
          ButtonSegment(value: 'ADJ', label: Text('ADJ')),
        ],
        selected: {w.chokeType},
        onSelectionChanged: (value) => setState(() => w.chokeType = value.first),
      ),
      const SizedBox(height: 12),
      _field('Choke', w.choke, suffix: w.chokeType == 'POS' ? '/64' : 'ADJ'),
      _field(isMach ? 'Water/hr' : 'BWPH', w.bwph, suffix: 'BBL/hr'),
      _field(isMach ? 'Oil/hr' : 'BOPH', w.boph, suffix: 'BBL/hr'),
      _field('Gas Spot Rate', w.gasSpot, suffix: 'MMCF/d'),
      _field('24hr Gas Rate', w.gas24, suffix: 'MCF'),
      _field('Sand', w.sand, suffix: 'GAL/hr'),
      _field('Diff', w.diff, suffix: 'PSI'),
      _field('Stat', w.stat, suffix: 'PSI'),
      _field('Temp', w.temp, suffix: '°'),
      _field('Prop', w.prop, suffix: 'GPH'),
      _field('H2O SG', w.h2oSg),
      _field('WHT', w.wht, suffix: '°'),
      _field('WTR TMP', w.wtrTmp, suffix: '°'),
      _field('Flare Rate', w.flareRate, suffix: 'MCF/d'),
      _field('Flare Pilot Temp', w.flarePilotTemp, suffix: '°'),
      _field('Biocide', w.biocide, suffix: 'GPD'),
      ExpansionTile(
        initiallyExpanded: true,
        title: const Text('VRU'),
        children: [
          _field('VRU Gas Rate', w.vruGas, suffix: 'MCF/d'),
          _field('VRU Suction', w.vruSuction, suffix: 'PSI'),
          _field('VRU Discharge', w.vruDischarge, suffix: 'PSI'),
        ],
      ),
      ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Compressor'),
        children: [
          _field('Compressor Company', w.compressorCompany, keyboardType: TextInputType.text),
          _field('Compressor Suction', w.compressorSuction, suffix: 'PSI'),
          _field('Compressor Discharge', w.compressorDischarge, suffix: 'PSI'),
          _field('Injection Rate', w.injectionRate, suffix: 'MCF'),
        ],
      ),
      _field('Notes', w.notes, keyboardType: TextInputType.multiline, lines: 3),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Text Update Builder', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _section('Heading shown once at top', [
            DropdownButtonFormField<String>(
              value: selectedTime,
              decoration: const InputDecoration(labelText: 'Update Time'),
              items: times.map((time) => DropdownMenuItem(value: time, child: Text(time))).toList(),
              onChanged: (value) => setState(() => selectedTime = value ?? selectedTime),
            ),
            const SizedBox(height: 12),
            _companyPicker(),
            const SizedBox(height: 12),
            if (selectedTemplate == 'Custom' || savedTemplates.containsKey(selectedTemplate))
              _field('Company Name', customCompanyName, keyboardType: TextInputType.text),
            _field('Well Pad / Location', padName, keyboardType: TextInputType.text),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _saveCustomTemplate, icon: const Icon(Icons.save), label: const Text('Save Template'))),
            ]),
          ]),
          for (int i = 0; i < wells.length; i++) _wellCard(i),
          OutlinedButton.icon(onPressed: _addWell, icon: const Icon(Icons.add), label: const Text('Add Well')),
          const SizedBox(height: 16),
          const Text('Preview', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(updateText, style: const TextStyle(height: 1.35, fontFamily: 'monospace')),
            ),
          ),
          FilledButton.icon(onPressed: _copy, icon: const Icon(Icons.copy), label: const Text('Copy Text Update')),
        ],
      ),
    );
  }
}

class SavedTemplate {
  final String name;
  final String base;
  final Map<String, bool> include;

  const SavedTemplate({required this.name, required this.base, required this.include});

  Map<String, dynamic> toJson() => {'name': name, 'base': base, 'include': include};

  factory SavedTemplate.fromJson(Map<String, dynamic> json) {
    return SavedTemplate(
      name: json['name'] as String? ?? 'Custom',
      base: json['base'] as String? ?? 'Continental Resources',
      include: (json['include'] as Map<String, dynamic>? ?? {}).map((key, value) => MapEntry(key, value == true)),
    );
  }
}

class WellUpdate {
  WellUpdate({required String name}) {
    wellName.text = name;
    applyContinental();
  }

  final wellName = TextEditingController();
  final csg = TextEditingController();
  final icp = TextEditingController();
  final choke = TextEditingController();
  final bwph = TextEditingController();
  final boph = TextEditingController();
  final gasSpot = TextEditingController();
  final gas24 = TextEditingController();
  final diff = TextEditingController();
  final stat = TextEditingController();
  final temp = TextEditingController();
  final prop = TextEditingController();
  final h2oSg = TextEditingController();
  final wht = TextEditingController();
  final wtrTmp = TextEditingController();
  final flareRate = TextEditingController();
  final flarePilotTemp = TextEditingController();
  final biocide = TextEditingController();
  final sand = TextEditingController();
  final vruGas = TextEditingController();
  final vruSuction = TextEditingController();
  final vruDischarge = TextEditingController();
  final compressorCompany = TextEditingController();
  final compressorSuction = TextEditingController();
  final compressorDischarge = TextEditingController();
  final injectionRate = TextEditingController();
  final notes = TextEditingController();

  String chokeType = 'ADJ';
  final Map<String, bool> include = {};

  bool on(String key) => include[key] ?? false;

  void applyContinental() {
    include
      ..clear()
      ..addAll({
        'csg': true,
        'icp': true,
        'choke': true,
        'bwph': true,
        'boph': true,
        'gasSpot': true,
        'gas24': true,
        'diff': true,
        'stat': true,
        'temp': true,
        'prop': true,
        'h2oSg': true,
        'wht': true,
        'wtrTmp': true,
        'flareRate': true,
        'flarePilotTemp': true,
        'biocide': true,
        'sand': false,
        'vru': true,
        'compressor': true,
        'notes': true,
      });
  }

  void applyMach() {
    include
      ..clear()
      ..addAll({
        'csg': true,
        'icp': false,
        'choke': true,
        'bwph': true,
        'boph': true,
        'gasSpot': false,
        'gas24': true,
        'diff': false,
        'stat': false,
        'temp': false,
        'prop': false,
        'h2oSg': false,
        'wht': false,
        'wtrTmp': false,
        'flareRate': false,
        'flarePilotTemp': false,
        'biocide': false,
        'sand': true,
        'vru': false,
        'compressor': false,
        'notes': true,
      });
  }

  void copyIncludesFrom(WellUpdate other) {
    include
      ..clear()
      ..addAll(other.include);
    chokeType = other.chokeType;
  }

  WellUpdate duplicate(String name) {
    final w = WellUpdate(name: name);
    w.copyIncludesFrom(this);
    w.csg.text = csg.text;
    w.icp.text = icp.text;
    w.choke.text = choke.text;
    w.bwph.text = bwph.text;
    w.boph.text = boph.text;
    w.gasSpot.text = gasSpot.text;
    w.gas24.text = gas24.text;
    w.diff.text = diff.text;
    w.stat.text = stat.text;
    w.temp.text = temp.text;
    w.prop.text = prop.text;
    w.h2oSg.text = h2oSg.text;
    w.wht.text = wht.text;
    w.wtrTmp.text = wtrTmp.text;
    w.flareRate.text = flareRate.text;
    w.flarePilotTemp.text = flarePilotTemp.text;
    w.biocide.text = biocide.text;
    w.sand.text = sand.text;
    w.vruGas.text = vruGas.text;
    w.vruSuction.text = vruSuction.text;
    w.vruDischarge.text = vruDischarge.text;
    w.compressorCompany.text = compressorCompany.text;
    w.compressorSuction.text = compressorSuction.text;
    w.compressorDischarge.text = compressorDischarge.text;
    w.injectionRate.text = injectionRate.text;
    w.notes.text = notes.text;
    return w;
  }

  List<TextEditingController> get controllers => [
        wellName,
        csg,
        icp,
        choke,
        bwph,
        boph,
        gasSpot,
        gas24,
        diff,
        stat,
        temp,
        prop,
        h2oSg,
        wht,
        wtrTmp,
        flareRate,
        flarePilotTemp,
        biocide,
        sand,
        vruGas,
        vruSuction,
        vruDischarge,
        compressorCompany,
        compressorSuction,
        compressorDischarge,
        injectionRate,
        notes,
      ];

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}
