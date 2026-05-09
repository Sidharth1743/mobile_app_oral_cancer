class OralSite {
  const OralSite({required this.id, required this.label});

  final String id;
  final String label;
}

const oralSites = [
  OralSite(id: 'left_buccal', label: 'Left buccal mucosa'),
  OralSite(id: 'right_buccal', label: 'Right buccal mucosa'),
  OralSite(id: 'tongue_lateral', label: 'Lateral tongue'),
  OralSite(id: 'floor_of_mouth', label: 'Floor of mouth'),
  OralSite(id: 'hard_palate', label: 'Hard palate'),
  OralSite(id: 'gingiva', label: 'Gingiva'),
];
