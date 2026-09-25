import 'package:flutter/material.dart';

import '../../net/ble_session.dart';
import '../../theme/palette.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.peers,
    required this.error,
    required this.onJoin,
    required this.onLeave,
  });

  final List<NearbyPeer> peers;
  final String? error;
  final ValueChanged<String> onJoin;
  final VoidCallback onLeave;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.pit,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Finding nearby phones', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Palette.ink)),
                  ),
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(color: Palette.glow, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'If you tapped first, wait here. The other phone taps you.',
                style: TextStyle(color: Palette.dust, height: 1.35),
              ),
              if (widget.error != null) ...[
                const SizedBox(height: 16),
                Text(widget.error!, style: const TextStyle(color: Palette.glow, fontSize: 16)),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: widget.peers.isEmpty
                    ? const Center(
                        child: Text('No phones yet.', style: TextStyle(color: Palette.beige, fontSize: 18)),
                      )
                    : ListView.separated(
                        itemCount: widget.peers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final peer = widget.peers[index];
                          final color = index.isEven ? Palette.beige : Palette.dust;
                          return Material(
                            color: const Color(0xFF2A241E),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: ValueKey('nearby-peer-$index'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => widget.onJoin(peer.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                                child: Row(
                                  children: [
                                    Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                    const SizedBox(width: 14),
                                    const Text('P1', style: TextStyle(color: Palette.ink, fontSize: 20, fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    Text('${peer.rssi}', style: const TextStyle(color: Palette.dust)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              TextButton(
                key: const ValueKey('search-leave'),
                onPressed: widget.onLeave,
                child: const Text('Leave', style: TextStyle(color: Palette.beige)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
