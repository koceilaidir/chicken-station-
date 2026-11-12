import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/repos.dart';
import '../ui/touch_keyboard.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Réglages › Menu (administrateur) : familles, produits, prix, photos, ordre.
class MenuAdminScreen extends StatefulWidget {
  const MenuAdminScreen({super.key});

  @override
  State<MenuAdminScreen> createState() => _MenuAdminScreenState();
}

class _MenuAdminScreenState extends State<MenuAdminScreen> {
  List<Family> _families = [];
  List<Product> _products = [];
  int? _familyId;
  int? _productId;
  List<String> _photos = [];

  final _famName = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();

  @override
  void initState() {
    super.initState();
    _photos = AppDb.I.listPhotos();
    _reloadFamilies();
  }

  @override
  void dispose() {
    _famName.dispose();
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Family? get _family => _families.where((f) => f.id == _familyId).firstOrNull;
  Product? get _product => _products.where((p) => p.id == _productId).firstOrNull;

  void _reloadFamilies() {
    _families = MenuRepo.families();
    if (_families.isNotEmpty && _family == null) _familyId = _families.first.id;
    _reloadProducts();
  }

  void _reloadProducts() {
    final f = _family;
    _famName.text = f?.name ?? '';
    _products = f == null ? [] : MenuRepo.products(f.id);
    if (_product == null) _productId = _products.isEmpty ? null : _products.first.id;
    _fillEditor();
    setState(() {});
  }

  void _fillEditor() {
    final p = _product;
    _name.text = p?.name ?? '';
    _price.text = p == null ? '' : '${p.price}';
    _desc.text = p?.description ?? '';
  }

  void _saveProduct() {
    final p = _product;
    if (p == null) return;
    p.name = _name.text.trim().isEmpty ? p.name : _name.text.trim();
    p.price = parseAmount(_price.text) ?? p.price;
    p.description = _desc.text.trim();
    MenuRepo.saveProduct(p);
    setState(() {});
  }

  void _moveProduct(Product p, int delta) {
    final list = List<Product>.from(_products);
    final i = list.indexOf(p);
    final j = delta == -100 ? 0 : i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    list.removeAt(i);
    list.insert(j, p);
    MenuRepo.reorderProducts(list);
    _reloadProducts();
  }

  void _moveFamily(Family f, int delta) {
    final list = List<Family>.from(_families);
    final i = list.indexOf(f);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    list.removeAt(i);
    list.insert(j, f);
    MenuRepo.reorderFamilies(list);
    _reloadFamilies();
  }

  Future<void> _addFamily() async {
    final name = await askText(context, 'Nouvelle famille', hint: 'ex. Boissons');
    if (name == null || name.isEmpty) return;
    _familyId = MenuRepo.addFamily(name);
    _productId = null;
    _reloadFamilies();
  }

  void _addProduct() {
    final f = _family;
    if (f == null) return;
    _productId = MenuRepo.addProduct(f.id, 'Nouveau produit', 0, f.photo);
    _reloadProducts();
  }

  Future<void> _deleteProduct(Product p) async {
    final ok = await confirm(context, 'Supprimer « ${p.name} » ?',
        'Le produit disparaît de la caisse. Les ventes passées restent dans l\'historique.', ok: 'Supprimer');
    if (!ok) return;
    MenuRepo.deleteProduct(p.id);
    _productId = null;
    _reloadProducts();
  }

  /// Choix de la photo de la famille (pastille ronde en caisse) dans la base d'images.
  Future<void> _pickFamilyPhoto(Family f) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Photo de la famille « ${f.name} »'),
          content: SizedBox(
            width: 640,
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('${_photos.length} photos dans la base', style: const TextStyle(color: AppColors.textSecondary)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Importer une photo…'),
                      onPressed: () async {
                        const group = XTypeGroup(label: 'Images', extensions: <String>['jpg', 'jpeg', 'png']);
                        final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
                        if (file == null) return;
                        final name = await AppDb.I.importPhotoFile(file.path);
                        _photos = AppDb.I.listPhotos();
                        if (c.mounted) Navigator.pop(c, name);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 110,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (_, i) {
                      final name = _photos[i];
                      final sel = name == f.photo;
                      return InkWell(
                        borderRadius: BorderRadius.circular(60),
                        onTap: () => Navigator.pop(c, name),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: sel ? AppColors.yellow : Colors.transparent, width: 3),
                          ),
                          child: PhotoBox(photo: name, radius: 60),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    f.photo = chosen;
    MenuRepo.saveFamily(f);
    setState(() {});
    toast(context, 'Photo de « ${f.name} » changée.');
  }

  Future<void> _deleteFamily(Family f) async {
    final n = MenuRepo.countProducts(f.id);
    final ok = await confirm(
      context,
      'Supprimer la famille « ${f.name} » ?',
      n == 0
          ? 'La famille est vide.'
          : 'Ses $n produit(s) seront supprimés aussi. Les ventes passées restent dans l\'historique.\n'
              'Pour la retirer de la caisse sans rien perdre, décochez plutôt « En caisse ».',
      ok: 'Supprimer',
    );
    if (!ok) return;
    MenuRepo.deleteFamily(f);
    _familyId = null;
    _productId = null;
    _reloadFamilies();
  }

  Future<void> _importPhotos() async {
    const group = XTypeGroup(label: 'Images', extensions: <String>['jpg', 'jpeg', 'png']);
    final files = await openFiles(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (files.isEmpty) return;
    String? last;
    for (final f in files) {
      last = await AppDb.I.importPhotoFile(f.path);
    }
    setState(() => _photos = AppDb.I.listPhotos());
    if (!mounted) return;
    toast(context, '${files.length} photo(s) ajoutée(s) à la base d\'images');
    final p = _product;
    if (p != null && last != null && files.length == 1) {
      p.photo = last;
      MenuRepo.saveProduct(p);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        children: [
          PageHeader(
            overline: 'Réglages',
            title: 'Menu',
            actions: [
              SecondaryButton(label: 'Importer des photos (clé USB)', onPressed: _importPhotos),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              // Petits écrans : colonnes plus étroites pour garder les trois panneaux visibles.
              builder: (context, c) {
                final small = c.maxWidth < 1050;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: small ? 190 : 240, child: _familiesCard()),
                    const SizedBox(width: 12),
                    Expanded(child: _productsCard()),
                    const SizedBox(width: 12),
                    SizedBox(width: small ? 280 : 330, child: _editorCard()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _familiesCard() {
    return IosCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(8, 6, 8, 6), child: SectionLabel('Familles')),
          Expanded(
            child: ListView.builder(
              itemCount: _families.length,
              itemBuilder: (c, i) {
                final f = _families[i];
                final sel = f.id == _familyId;
                return Material(
                  color: sel ? AppColors.yellowSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _familyId = f.id;
                      _productId = null;
                      _reloadProducts();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          PhotoBox(photo: f.photo, size: 34, radius: 17, fallback: f.name),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(f.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, color: f.active ? AppColors.text : AppColors.textSecondary)),
                          ),
                          if (sel) ...[
                            InkWell(onTap: () => _moveFamily(f, -1), child: const Icon(Icons.keyboard_arrow_up, size: 20)),
                            InkWell(onTap: () => _moveFamily(f, 1), child: const Icon(Icons.keyboard_arrow_down, size: 20)),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: 'Supprimer la famille',
                              child: InkWell(
                                onTap: () => _deleteFamily(f),
                                child: const Icon(Icons.delete_outline, size: 19, color: AppColors.redText),
                              ),
                            ),
                          ] else
                            Text('${MenuRepo.countProducts(f.id)}', style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SecondaryButton(label: '+ Nouvelle famille', onPressed: _addFamily),
        ],
      ),
    );
  }

  Widget _productsCard() {
    final f = _family;
    return IosCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (f != null) ...[
                Tooltip(
                  message: 'Changer la photo de la famille',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => _pickFamilyPhoto(f),
                    child: Stack(
                      children: [
                        PhotoBox(photo: f.photo, size: 52, radius: 26, fallback: f.name),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                            child: const Icon(Icons.edit, size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: TextField(
                  controller: _famName,
                  enabled: f != null,
                  readOnly: TouchKeyboard.enabled,
                  showCursor: true,
                  onTap: TouchKeyboard.enabled && f != null
                      ? () => TouchKeyboard.open(_famName, onChanged: (v) {
                            if (v.trim().isEmpty) return;
                            f.name = v.trim();
                            MenuRepo.saveFamily(f);
                          }, onSubmitted: (_) => setState(() {}))
                      : null,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, labelText: 'Nom de la famille'),
                  onChanged: (v) {
                    if (f == null || v.trim().isEmpty) return;
                    f.name = v.trim();
                    MenuRepo.saveFamily(f);
                  },
                  onSubmitted: (_) => setState(() {}),
                ),
              ),
              if (f != null)
                Row(
                  children: [
                    const Text('En caisse', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Switch(
                      value: f.active,
                      activeTrackColor: AppColors.green,
                      onChanged: (v) {
                        f.active = v;
                        MenuRepo.saveFamily(f);
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 6),
                    const Text('En cuisine', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Tooltip(
                      message: 'Désactivé : ces produits ne sortent pas sur le bon cuisine (ex. boissons).',
                      child: Switch(
                        value: f.kitchen,
                        activeTrackColor: AppColors.green,
                        onChanged: (v) {
                          f.kitchen = v;
                          MenuRepo.saveFamily(f);
                          logActivity('famille_modifiee', '${f.name} · ${v ? 'envoyée' : 'plus envoyée'} en cuisine');
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 8),
              PrimaryButton(label: '+ Produit', onPressed: f == null ? null : _addProduct),
            ],
          ),
          Text('${_products.length} produits · les flèches changent l\'ordre en caisse',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Expanded(
            child: _products.isEmpty
                ? const Center(child: Text('Aucun produit. Touchez « + Produit ».'))
                : ListView.builder(
                    itemCount: _products.length,
                    itemBuilder: (c, i) {
                      final p = _products[i];
                      final sel = p.id == _productId;
                      return Opacity(
                        opacity: p.active ? 1 : 0.5,
                        child: Material(
                          color: sel ? AppColors.yellowSoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() {
                              _productId = p.id;
                              _fillEditor();
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                      width: 24,
                                      child: Text('${i + 1}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                                  const SizedBox(width: 6),
                                  PhotoBox(photo: p.photo, size: 44, fallback: p.name),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Text('${fmtDa(p.price)}${p.active ? '' : ' · masqué'}',
                                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Monter',
                                      onPressed: () => _moveProduct(p, -1),
                                      icon: const Icon(Icons.keyboard_arrow_up)),
                                  IconButton.filledTonal(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Descendre',
                                      onPressed: () => _moveProduct(p, 1),
                                      icon: const Icon(Icons.keyboard_arrow_down)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _editorCard() {
    final p = _product;
    if (p == null) {
      return const IosCard(child: Center(child: Text('Sélectionnez un produit pour le modifier')));
    }
    return IosCard(
      padding: const EdgeInsets.all(14),
      child: ListView(
        children: [
          Stack(
            children: [
              PhotoBox(photo: p.photo, width: double.infinity, height: 130, fallback: p.name),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _deleteProduct(p),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppColors.redText),
                          SizedBox(width: 4),
                          Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.redText)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Nom', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FieldBox(controller: _name, onChanged: (_) => _saveProduct()),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Prix (DA)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    FieldBox(controller: _price, numeric: true, onChanged: (_) => _saveProduct()),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  const Text('En caisse', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Switch(
                    value: p.active,
                    activeTrackColor: AppColors.green,
                    onChanged: (v) {
                      p.active = v;
                      MenuRepo.saveProduct(p);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Description', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FieldBox(controller: _desc, onChanged: (_) => _saveProduct()),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Photo · base d\'images', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Spacer(),
              Text('${_photos.length} photos', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 200,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 6, mainAxisSpacing: 6),
              itemCount: _photos.length,
              itemBuilder: (c, i) {
                final name = _photos[i];
                final sel = name == p.photo;
                return InkWell(
                  onTap: () {
                    p.photo = name;
                    MenuRepo.saveProduct(p);
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? AppColors.yellow : Colors.transparent, width: 2.5),
                    ),
                    child: PhotoBox(photo: name, radius: 7),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SecondaryButton(label: 'Mettre en premier', onPressed: () => _moveProduct(p, -100)),
          const SizedBox(height: 6),
          const Text('Modifications enregistrées automatiquement',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          TextButton(
            onPressed: () {
              final f = _family;
              if (f == null) return;
              f.photo = p.photo;
              MenuRepo.saveFamily(f);
              setState(() {});
              toast(context, 'Photo utilisée pour la famille « ${f.name} »');
            },
            child: const Text('Utiliser cette photo pour la famille'),
          ),
        ],
      ),
    );
  }
}
