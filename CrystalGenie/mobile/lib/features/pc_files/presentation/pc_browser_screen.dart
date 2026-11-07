import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/images.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/pc_files_repository.dart';

/// "This computer": browse folders on the PC that runs the backend and pick a photo to identify.
class PcBrowserScreen extends ConsumerStatefulWidget {
  const PcBrowserScreen({super.key});
  @override
  ConsumerState<PcBrowserScreen> createState() => _PcBrowserScreenState();
}

class _PcBrowserScreenState extends ConsumerState<PcBrowserScreen> {
  /// Folder history; empty = the list of drives/root folders.
  final List<String> _stack = [];
  bool _opening = false;

  String? get _current => _stack.isEmpty ? null : _stack.last;

  void _open(String path) => setState(() => _stack.add(path));

  bool _goUp() {
    if (_stack.isEmpty) return false;
    setState(_stack.removeLast);
    return true;
  }

  Future<void> _pick(PcImage img) async {
    setState(() => _opening = true);
    try {
      final local = await ref.read(pcFilesRepositoryProvider).download(img);
      if (mounted) context.push(Routes.preview, extra: local);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return PopScope(
      canPop: _stack.isEmpty && !_opening,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_opening) _goUp();
      },
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                      child: Row(children: [
                        IconButton(
                          key: const Key('pc_back'),
                          tooltip: context.tr('Back'),
                          onPressed: () {
                            if (!_goUp()) context.pop();
                          },
                          icon: const Icon(Icons.chevron_left, size: 30),
                        ),
                        const Icon(Icons.computer_outlined, color: AppColors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(context.tr('This computer'),
                              style: AppText.montserrat(size: 21, weight: FontWeight.w700, color: AppColors.teal)),
                        ),
                      ]),
                    ),
                    if (current != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(current,
                            key: const Key('pc_path'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.montserrat(size: 12, color: AppColors.darkGrey)),
                      ),
                    Expanded(child: current == null ? _roots() : _folder(current)),
                  ],
                ),
                if (_opening)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black26,
                      child: LoadingView(message: context.tr('Opening photo…')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roots() {
    final async = ref.watch(pcRootsProvider);
    return async.when(
      loading: () => LoadingView(message: context.tr('Loading folder…')),
      error: (e, _) => ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(pcRootsProvider)),
      data: (roots) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(context.tr('Choose a folder on your PC, then tap a photo to identify it.'),
                style: AppText.montserrat(size: 13, color: AppColors.darkGrey)),
          ),
          for (final r in roots)
            _FolderTile(
                key: ValueKey('pc_root_${r.path}'),
                name: r.name,
                subtitle: r.path,
                icon: r.kind == 'place' ? _placeIcon(r.name) : Icons.storage_rounded,
                onTap: () => _open(r.path)),
        ],
      ),
    );
  }

  Widget _folder(String path) {
    final async = ref.watch(pcListingProvider(path));
    final repo = ref.read(pcFilesRepositoryProvider);
    return async.when(
      loading: () => LoadingView(message: context.tr('Loading folder…')),
      error: (e, _) => ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(pcListingProvider(path))),
      data: (l) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(pcListingProvider(path)),
        child: CustomScrollView(
          key: const Key('pc_list'),
          slivers: [
            if (l.folders.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.list(children: [
                  for (final f in l.folders)
                    _FolderTile(key: ValueKey('pc_folder_${f.name}'), name: f.name, icon: Icons.folder_rounded, onTap: () => _open(f.path)),
                ]),
              ),
            if (l.images.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('${context.tr('Photos')} (${l.images.length})',
                      style: AppText.montserrat(size: 15, weight: FontWeight.w700, color: AppColors.navy)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                  itemCount: l.images.length,
                  itemBuilder: (_, i) {
                    final img = l.images[i];
                    return Semantics(
                      button: true,
                      label: img.name,
                      child: GestureDetector(
                        key: ValueKey('pc_image_${img.name}'),
                        onTap: _opening ? null : () => _pick(img),
                        child: ApiImage(repo.thumbnailPath(img.path), radius: 10),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (l.folders.isEmpty && l.images.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(context.tr('No folders or photos here.'),
                      key: const Key('pc_empty'), style: AppText.montserrat(size: 15, color: AppColors.darkGrey)),
                ),
              ),
            if (l.truncated)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.tr('Only the first 1000 items are shown.'),
                      textAlign: TextAlign.center, style: AppText.montserrat(size: 12, color: AppColors.grey)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _placeIcon(String name) => switch (name.toLowerCase()) {
      'desktop' => Icons.desktop_windows_outlined,
      'pictures' => Icons.photo_library_outlined,
      'downloads' => Icons.download_outlined,
      'documents' => Icons.description_outlined,
      _ => Icons.folder_rounded,
    };

class _FolderTile extends StatelessWidget {
  const _FolderTile({super.key, required this.name, required this.icon, required this.onTap, this.subtitle});
  final String name;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          radius: 14,
          padding: EdgeInsets.zero,
          borderColor: AppColors.mint,
          onTap: onTap,
          child: ListTile(
            leading: Icon(icon, color: AppColors.sky, size: 30),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.montserrat(size: 15, weight: FontWeight.w600)),
            subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      );
}
