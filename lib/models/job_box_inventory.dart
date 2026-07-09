import 'package:intl/intl.dart';

class JobBoxInventoryItem {
  const JobBoxInventoryItem({
    required this.key,
    required this.name,
    required this.quantity,
    required this.section,
    required this.isDefault,
    required this.canDelete,
  });

  final String key;
  final String name;
  final int quantity;
  final String section;
  final bool isDefault;
  final bool canDelete;

  JobBoxInventoryItem copyWith({
    String? key,
    String? name,
    int? quantity,
    String? section,
    bool? isDefault,
    bool? canDelete,
  }) {
    return JobBoxInventoryItem(
      key: key ?? this.key,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      section: section ?? this.section,
      isDefault: isDefault ?? this.isDefault,
      canDelete: canDelete ?? this.canDelete,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'quantity': quantity,
        'section': section,
        'isDefault': isDefault,
        'canDelete': canDelete,
      };

  factory JobBoxInventoryItem.fromJson(Map<String, dynamic> json) {
    return JobBoxInventoryItem(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      section: json['section'] as String? ?? 'main',
      isDefault: json['isDefault'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
    );
  }
}

class JobBoxInventoryCatalog {
  static const mainSection = 'main';
  static const positiveChokesSection = 'positive_chokes';
  static const customSection = 'custom';

  static const defaultItems = <JobBoxInventoryItem>[
    JobBoxInventoryItem(
      key: '916m_x_916m_ac',
      name: '9/16 M x 9/16 M AC',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '916m_x_12npt_ac',
      name: '9/16 M x 1/2 NPT AC',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '1k_gauge',
      name: '1K Gauge',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '2k_gauge',
      name: '2K Gauge',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '3k_gauge',
      name: '3K Gauge',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '5k_gauge',
      name: '5K Gauge',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '10k_gauge',
      name: '10K Gauge',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '15k_gauge',
      name: '15K Gauge',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '10k_needle_valve',
      name: '10K Needle Valve',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '30k_needle_valve',
      name: '30K Needle Valve',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '2_viton_seal',
      name: '2" Viton Seal',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '3_viton_seal',
      name: '3" Viton Seal',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '4_seal',
      name: '4" Seal',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '4_viton_seals',
      name: '4" Viton Seals',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '34_seat',
      name: '3/4" Seat',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '1_seat',
      name: '1" Seat',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '1_stem',
      name: '1" Stem',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '2_seat',
      name: '2" Seat',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '2_stem',
      name: '2" Stem',
      quantity: 0,
      section: mainSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '12_64',
      name: '12/64',
      quantity: 0,
      section: positiveChokesSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '13_64',
      name: '13/64',
      quantity: 0,
      section: positiveChokesSection,
      isDefault: true,
      canDelete: false,
    ),
    JobBoxInventoryItem(
      key: '14_64',
      name: '14/64',
      quantity: 0,
      section: positiveChokesSection,
      isDefault: true,
      canDelete: false,
    ),
  ];

  static String sectionLabel(String section) {
    switch (section) {
      case positiveChokesSection:
        return 'Positive Chokes';
      case customSection:
        return 'Custom Items';
      default:
        return 'Main Inventory';
    }
  }
}

class JobBoxInventoryRecord {
  const JobBoxInventoryRecord({
    required this.id,
    required this.date,
    required this.wellNames,
    required this.jobBoxNumber,
    required this.hideZeroQuantityItems,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String date;
  final String wellNames;
  final String jobBoxNumber;
  final bool hideZeroQuantityItems;
  final List<JobBoxInventoryItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  JobBoxInventoryRecord copyWith({
    String? id,
    String? date,
    String? wellNames,
    String? jobBoxNumber,
    bool? hideZeroQuantityItems,
    List<JobBoxInventoryItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JobBoxInventoryRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      wellNames: wellNames ?? this.wellNames,
      jobBoxNumber: jobBoxNumber ?? this.jobBoxNumber,
      hideZeroQuantityItems:
          hideZeroQuantityItems ?? this.hideZeroQuantityItems,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'wellNames': wellNames,
        'jobBoxNumber': jobBoxNumber,
        'hideZeroQuantityItems': hideZeroQuantityItems,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory JobBoxInventoryRecord.fromJson(Map<String, dynamic> json) {
    return JobBoxInventoryRecord(
      id: json['id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      wellNames: json['wellNames'] as String? ?? '',
      jobBoxNumber: json['jobBoxNumber'] as String? ?? '',
      hideZeroQuantityItems: json['hideZeroQuantityItems'] as bool? ?? false,
      items: ((json['items'] as List?) ?? const [])
          .map((item) => JobBoxInventoryItem.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  factory JobBoxInventoryRecord.createDefault() {
    final now = DateTime.now();
    return JobBoxInventoryRecord(
      id: '',
      date: DateFormat('MM/dd/yyyy').format(now),
      wellNames: '',
      jobBoxNumber: '',
      hideZeroQuantityItems: false,
      items: [
        for (final item in JobBoxInventoryCatalog.defaultItems)
          item.copyWith(quantity: 0),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  List<JobBoxInventoryItem> get mainItems => items
      .where((item) => item.section == JobBoxInventoryCatalog.mainSection)
      .toList();

  List<JobBoxInventoryItem> get positiveChokes => items
      .where((item) =>
          item.section == JobBoxInventoryCatalog.positiveChokesSection)
      .toList();

  List<JobBoxInventoryItem> get customItems => items
      .where((item) => item.section == JobBoxInventoryCatalog.customSection)
      .toList();

  List<JobBoxInventoryItem> get visibleItems => items
      .where((item) => !hideZeroQuantityItems || item.quantity > 0)
      .toList();

  String get copyHeading => 'Job Box Inventory';
}
