import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dragy_provider.dart';
import '../models/vehicle.dart';

class GarageScreen extends StatelessWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final vehicles = dragy.vehicles;
    final activeId = dragy.activeVehicleId;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Garage',
          style: GoogleFonts.comfortaa(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFFFBF00)),
            onPressed: () => _showVehicleForm(context, null),
          ),
        ],
      ),
      body: vehicles.isEmpty
          ? _EmptyGarageView(onAdd: () => _showVehicleForm(context, null))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: vehicles.length,
              itemBuilder: (context, index) {
                final v = vehicles[index];
                final isActive = v.id == activeId;
                return _VehicleCard(
                  vehicle: v,
                  isActive: isActive,
                  onSelect: () => dragy.setActiveVehicle(v.id),
                  onEdit: () => _showVehicleForm(context, v),
                  onDelete: () => _confirmDelete(context, dragy, v),
                );
              },
            ),
    );
  }

  void _confirmDelete(
      BuildContext context, DragyProvider dragy, Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete Vehicle',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${vehicle.displayName} from your garage?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              dragy.deleteVehicle(vehicle.id);
              Navigator.pop(ctx);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showVehicleForm(BuildContext context, Vehicle? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VehicleFormSheet(existing: existing),
    );
  }
}

class _EmptyGarageView extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGarageView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car_outlined,
              size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            'Your garage is empty.',
            style: const TextStyle(color: Colors.white54, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a vehicle to link it to your runs.',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Vehicle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VehicleCard({
    required this.vehicle,
    required this.isActive,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFFBF00).withOpacity(0.07)
              : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFFBF00).withOpacity(0.6)
                : Colors.white.withOpacity(0.07),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFBF00).withOpacity(0.1),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Car icon with active indicator
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFFFBF00).withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_car,
                  color:
                      isActive ? const Color(0xFFFFBF00) : Colors.white54,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              // Vehicle info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vehicle.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFBF00).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    const Color(0xFFFFBF00).withOpacity(0.5),
                              ),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Color(0xFFFFBF00),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white38),
                color: Colors.grey.shade900,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined,
                            color: Colors.white54, size: 18),
                        SizedBox(width: 10),
                        Text('Edit',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            color: Colors.redAccent, size: 18),
                        SizedBox(width: 10),
                        Text('Delete',
                            style:
                                TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleFormSheet extends StatefulWidget {
  final Vehicle? existing;
  const _VehicleFormSheet({this.existing});

  @override
  State<_VehicleFormSheet> createState() => _VehicleFormSheetState();
}

class _VehicleFormSheetState extends State<_VehicleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _makeCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _yearCtrl;

  static const List<String> _popularBrands = [
    'Acura',
    'Alfa Romeo',
    'Aston Martin',
    'Audi',
    'BMW',
    'Chevrolet',
    'Dodge',
    'Ferrari',
    'Ford',
    'Honda',
    'Hyundai',
    'Jaguar',
    'Kia',
    'Lamborghini',
    'Lexus',
    'Lotus',
    'Maserati',
    'Mazda',
    'McLaren',
    'Mercedes-Benz',
    'MINI',
    'Mitsubishi',
    'Nissan',
    'Porsche',
    'Ram',
    'Subaru',
    'Tesla',
    'Toyota',
    'Volkswagen',
    'Volvo',
    'Other',
  ];

  String? _selectedBrand;
  bool _isCustomBrand = false;

  @override
  void initState() {
    super.initState();
    final existingMake = widget.existing?.make ?? '';
    _modelCtrl = TextEditingController(text: widget.existing?.model ?? '');
    _yearCtrl = TextEditingController(
        text: widget.existing?.year.toString() ?? '');

    if (existingMake.isEmpty) {
      _selectedBrand = null;
      _isCustomBrand = false;
      _makeCtrl = TextEditingController();
    } else if (_popularBrands.contains(existingMake)) {
      _selectedBrand = existingMake;
      _isCustomBrand = false;
      _makeCtrl = TextEditingController(text: existingMake);
    } else {
      _selectedBrand = 'Other';
      _isCustomBrand = true;
      _makeCtrl = TextEditingController(text: existingMake);
    }
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final dragy =
        Provider.of<DragyProvider>(context, listen: false);
    final year = int.tryParse(_yearCtrl.text.trim()) ?? DateTime.now().year;
    final brand = _isCustomBrand ? _makeCtrl.text.trim() : (_selectedBrand ?? '');

    if (widget.existing != null) {
      dragy.updateVehicle(widget.existing!.copyWith(
        make: brand,
        model: _modelCtrl.text.trim(),
        year: year,
      ));
    } else {
      dragy.addVehicle(Vehicle(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        make: brand,
        model: _modelCtrl.text.trim(),
        year: year,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  isEdit ? 'Edit Vehicle' : 'Add Vehicle',
                  style: GoogleFonts.comfortaa(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                // Brand Dropdown Selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedBrand,
                  dropdownColor: const Color(0xFF1F1F1F),
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFFBF00)),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Brand',
                    labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFBF00), width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.redAccent, width: 1.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  items: _popularBrands.map((brand) {
                    return DropdownMenuItem<String>(
                      value: brand,
                      child: Text(brand, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedBrand = val;
                      _isCustomBrand = val == 'Other';
                    });
                  },
                  validator: (val) => val == null ? 'Required' : null,
                ),
                if (_isCustomBrand) ...[
                  const SizedBox(height: 16),
                  _StyledField(
                    controller: _makeCtrl,
                    label: 'Custom Brand Name',
                    hint: 'e.g. Shelby',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: 16),
                // Model and Year Row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _StyledField(
                        controller: _modelCtrl,
                        label: 'Model',
                        hint: 'e.g. M3',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _StyledField(
                        controller: _yearCtrl,
                        label: 'Year',
                        hint: '2023',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 1900 || n > 2100) {
                            return 'Invalid';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isEdit ? 'Save Changes' : 'Add to Garage',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _StyledField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: 1,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: const Color(0xFFFFBF00),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFFFFBF00), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }
}
