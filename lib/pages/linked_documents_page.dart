import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:untitled1/services/linked_document_action_service.dart';
import 'package:untitled1/utils/document_chain_cancellation.dart';

enum _ChainFilter { all, open, paid, cancelled }

enum _ChainSort { newest, oldest, amount }

enum _ChainStatus {
  open,
  partiallyPaid,
  partiallyCancelled,
  completed,
  cancelled,
}

class LinkedDocumentsPage extends StatefulWidget {
  const LinkedDocumentsPage({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.externalClientNumber,
    required this.locale,
    this.embedded = false,
  });

  final String clientId;
  final String clientName;
  final String externalClientNumber;
  final String locale;
  final bool embedded;

  @override
  State<LinkedDocumentsPage> createState() => _LinkedDocumentsPageState();
}

class _LinkedDocumentsPageState extends State<LinkedDocumentsPage> {
  final _searchController = TextEditingController();
  _ChainFilter _filter = _ChainFilter.all;
  _ChainSort _sort = _ChainSort.newest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final strings = _LinkedDocumentStrings(widget.locale);
    final content = user == null
        ? _EmptyState(
            icon: Icons.lock_outline_rounded,
            title: strings.signIn,
            message: strings.signInMessage,
          )
        : _buildClientDocuments(context, user.uid, strings);

    if (widget.embedded) {
      return ColoredBox(
        color: const Color(0xFFF7FBFF),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.clientName.trim().isEmpty
                        ? strings.subtitle
                        : '${widget.clientName} • ${strings.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.title,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              widget.clientName.trim().isEmpty
                  ? strings.subtitle
                  : '${widget.clientName} • ${strings.subtitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: content,
    );
  }

  Widget _buildClientDocuments(
    BuildContext context,
    String userId,
    _LinkedDocumentStrings strings,
  ) {
    final invoices = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('invoices');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: invoices
          .where('savedClientId', isEqualTo: widget.clientId)
          .snapshots(),
      builder: (context, clientSnapshot) {
        if (clientSnapshot.hasError) return _loadError(strings);
        if (!clientSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (widget.externalClientNumber.trim().isEmpty) {
          return _buildContent(
            context,
            userId,
            clientSnapshot.data!.docs,
            strings,
          );
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: invoices
              .where(
                'externalClientNumber',
                isEqualTo: widget.externalClientNumber.trim(),
              )
              .snapshots(),
          builder: (context, legacySnapshot) {
            if (legacySnapshot.hasError) return _loadError(strings);
            if (!legacySnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
              for (final document in clientSnapshot.data!.docs)
                document.id: document,
              for (final document in legacySnapshot.data!.docs)
                document.id: document,
            };
            return _buildContent(
              context,
              userId,
              byId.values.toList(growable: false),
              strings,
            );
          },
        );
      },
    );
  }

  Widget _loadError(_LinkedDocumentStrings strings) => _EmptyState(
    icon: Icons.cloud_off_rounded,
    title: strings.loadFailed,
    message: strings.tryAgain,
  );

  Widget _buildContent(
    BuildContext context,
    String userId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> snapshots,
    _LinkedDocumentStrings strings,
  ) {
    final documents = snapshots
        .map(_LinkedDocument.fromSnapshot)
        .toList(growable: false);
    final graph = _DocumentGraph.fromDocuments(documents);
    var chains = graph.chains
        .where((chain) {
          final query = _searchController.text.trim().toLowerCase();
          if (query.isNotEmpty && !chain.matches(query, strings)) return false;
          return switch (_filter) {
            _ChainFilter.all => true,
            _ChainFilter.open =>
              chain.status == _ChainStatus.open ||
                  chain.status == _ChainStatus.partiallyPaid ||
                  chain.status == _ChainStatus.partiallyCancelled,
            _ChainFilter.paid => chain.status == _ChainStatus.completed,
            _ChainFilter.cancelled => chain.status == _ChainStatus.cancelled,
          };
        })
        .toList(growable: false);
    chains.sort(
      (a, b) => switch (_sort) {
        _ChainSort.newest => b.date.compareTo(a.date),
        _ChainSort.oldest => a.date.compareTo(b.date),
        _ChainSort.amount => b.total.compareTo(a.total),
      },
    );

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: strings.searchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: strings.clear,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: const Color(0xFFF1F5FB),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PopupMenuButton<_ChainSort>(
                    tooltip: strings.sort,
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _ChainSort.newest,
                        child: Text(strings.newest),
                      ),
                      PopupMenuItem(
                        value: _ChainSort.oldest,
                        child: Text(strings.oldest),
                      ),
                      PopupMenuItem(
                        value: _ChainSort.amount,
                        child: Text(strings.highestAmount),
                      ),
                    ],
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5FB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.filter_list_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip(
                      _ChainFilter.all,
                      '${strings.all} (${graph.chains.length})',
                    ),
                    _filterChip(
                      _ChainFilter.open,
                      '${strings.open} (${graph.openCount})',
                    ),
                    _filterChip(
                      _ChainFilter.paid,
                      '${strings.paid} (${graph.paidCount})',
                    ),
                    _filterChip(
                      _ChainFilter.cancelled,
                      '${strings.cancelled} (${graph.cancelledCount})',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: documents.isEmpty
              ? _EmptyState(
                  icon: Icons.account_tree_outlined,
                  title: strings.noDocuments,
                  message: strings.noDocumentsMessage,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 34),
                  children: [
                    if (chains.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 72),
                        child: _EmptyState(
                          icon: Icons.search_off_rounded,
                          title: strings.noResults,
                          message: strings.noResultsMessage,
                        ),
                      )
                    else
                      for (var index = 0; index < chains.length; index++) ...[
                        _ChainCard(
                          chain: chains[index],
                          number: graph.chains.indexOf(chains[index]) + 1,
                          locale: widget.locale,
                          strings: strings,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _ChainDetailPage(
                                chain: chains[index],
                                number: graph.chains.indexOf(chains[index]) + 1,
                                userId: userId,
                                locale: widget.locale,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    if (graph.standalone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _StandaloneCard(
                        count: graph.standalone.length,
                        strings: strings,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _StandaloneDocumentsPage(
                              documents: graph.standalone,
                              userId: userId,
                              locale: widget.locale,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _filterChip(_ChainFilter filter, String label) {
    final selected = _filter == filter;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => setState(() => _filter = filter),
        label: Text(label),
        showCheckmark: false,
        selectedColor: const Color(0xFF1687F8),
        backgroundColor: const Color(0xFFF1F5FB),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF334155),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({
    required this.chain,
    required this.number,
    required this.locale,
    required this.strings,
    required this.onTap,
  });

  final _DocumentChain chain;
  final int number;
  final String locale;
  final _LinkedDocumentStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stages = chain.stages;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDCE8F4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x090F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '${strings.chain} #$number',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusPill(status: chain.status, strings: strings),
                  const Spacer(),
                  Text(
                    _formatDate(chain.date),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < stages.length; index++) ...[
                      _ChainStage(stage: stages[index], strings: strings),
                      if (index != stages.length - 1)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 7),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                        ),
                    ],
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF334155),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Text(
                    strings.documentCount(chain.documents.length),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      '•',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                  Text(
                    _formatMoney(chain.total, locale),
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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

class _ChainStage extends StatelessWidget {
  const _ChainStage({required this.stage, required this.strings});

  final List<_LinkedDocument> stage;
  final _LinkedDocumentStrings strings;

  @override
  Widget build(BuildContext context) {
    final document = stage.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DocumentIcon(document: document, size: 42),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage.length == 1
                  ? strings.typeName(document.type)
                  : '${stage.length} ${strings.pluralTypeName(document.type)}',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              stage.length == 1 && document.number.isNotEmpty
                  ? '#${document.number}'
                  : strings.documentCount(stage.length),
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChainDetailPage extends StatelessWidget {
  const _ChainDetailPage({
    required this.chain,
    required this.number,
    required this.userId,
    required this.locale,
  });

  final _DocumentChain chain;
  final int number;
  final String userId;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final strings = _LinkedDocumentStrings(locale);
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${strings.chain} #$number',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            _StatusPill(status: chain.status, strings: strings),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: strings.more,
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(strings.documentCount(chain.documents.length)),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
          children: [
            _ChainTotalsCard(chain: chain, locale: locale, strings: strings),
            const SizedBox(height: 22),
            _DocumentTree(
              chain: chain,
              availableWidth: constraints.maxWidth - 32,
              locale: locale,
              strings: strings,
              onOpen: (document) => LinkedDocumentActionService.show(
                context: context,
                userId: userId,
                documentId: document.id,
                documentData: document.data,
                locale: locale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainTotalsCard extends StatelessWidget {
  const _ChainTotalsCard({
    required this.chain,
    required this.locale,
    required this.strings,
  });

  final _DocumentChain chain;
  final String locale;
  final _LinkedDocumentStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE8F4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _TotalColumn(
                label: strings.totalAmount,
                value: _formatMoney(chain.total, locale),
              ),
              const _VerticalDivider(),
              _TotalColumn(
                label: strings.paidAmount,
                value: _formatMoney(chain.paid, locale),
              ),
              const _VerticalDivider(),
              _TotalColumn(
                label: strings.remaining,
                value: _formatMoney(chain.remaining, locale),
                color: chain.remaining > 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF059669),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                strings.documentCount(chain.documents.length),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9),
                child: Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              Expanded(
                child: Text(
                  '${strings.created}: ${_formatDate(chain.createdDate)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalColumn extends StatelessWidget {
  const _TotalColumn({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(
              color: color ?? const Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 52,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: const Color(0xFFE2E8F0),
  );
}

class _DocumentTree extends StatelessWidget {
  const _DocumentTree({
    required this.chain,
    required this.availableWidth,
    required this.locale,
    required this.strings,
    required this.onOpen,
  });

  final _DocumentChain chain;
  final double availableWidth;
  final String locale;
  final _LinkedDocumentStrings strings;
  final ValueChanged<_LinkedDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    const cardWidth = 184.0;
    // Two independent status pills can wrap onto separate lines.
    const cardHeight = 140.0;
    const horizontalGap = 22.0;
    const verticalGap = 64.0;
    final levels = chain.levels;
    final centers = <String, double>{};
    var nextLeafSlot = 0.0;
    late double Function(_LinkedDocument document) placeSubtree;
    placeSubtree = (document) {
      final existing = centers[document.id];
      if (existing != null) return existing;
      final children =
          <_LinkedDocument>[
            ...(chain.childrenById[document.id] ?? const <_LinkedDocument>[]),
          ]..sort((a, b) {
            final dateComparison = a.date.compareTo(b.date);
            return dateComparison != 0
                ? dateComparison
                : a.number.compareTo(b.number);
          });
      if (children.isEmpty) {
        final slot = nextLeafSlot++;
        centers[document.id] = slot;
        return slot;
      }
      final childCenters = children.map(placeSubtree).toList(growable: false);
      final center = childCenters.reduce((a, b) => a + b) / childCenters.length;
      centers[document.id] = center;
      return center;
    };
    for (final root in levels.first) {
      placeSubtree(root);
    }
    for (final document in chain.documents) {
      placeSubtree(document);
    }

    // A document can legally reference more than one source. Keep cards on
    // the same row from overlapping in that less-common graph shape.
    for (final level in levels) {
      final ordered = [...level]
        ..sort((a, b) => centers[a.id]!.compareTo(centers[b.id]!));
      double? previous;
      for (final document in ordered) {
        final desired = centers[document.id]!;
        final resolved = previous == null
            ? desired
            : math.max(desired, previous + 1);
        centers[document.id] = resolved;
        previous = resolved;
      }
    }

    final minimumCenter = centers.values.reduce(math.min);
    final maximumCenter = centers.values.reduce(math.max);
    final slotWidth = cardWidth + horizontalGap;
    final contentWidth =
        (maximumCenter - minimumCenter) * slotWidth + cardWidth;
    final canvasWidth = math.max(availableWidth, contentWidth);
    final canvasHeight =
        levels.length * cardHeight +
        math.max(0, levels.length - 1) * verticalGap;
    final rects = <String, Rect>{};
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    for (var levelIndex = 0; levelIndex < levels.length; levelIndex++) {
      final level = levels[levelIndex];
      for (final document in level) {
        final logicalX =
            (canvasWidth - contentWidth) / 2 +
            (centers[document.id]! - minimumCenter) * slotWidth;
        final visualX = isRtl ? canvasWidth - logicalX - cardWidth : logicalX;
        rects[document.id] = Rect.fromLTWH(
          visualX,
          levelIndex * (cardHeight + verticalGap),
          cardWidth,
          cardHeight,
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TreeConnectorPainter(
                  rects: rects,
                  childrenById: chain.childrenById,
                ),
              ),
            ),
            for (final document in chain.documents)
              if (rects[document.id] case final rect?)
                Positioned.fromRect(
                  rect: rect,
                  child: _TreeDocumentCard(
                    document: document,
                    displayStatuses: chain.displayStatusesFor(document),
                    locale: locale,
                    strings: strings,
                    onTap: () => onOpen(document),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TreeConnectorPainter extends CustomPainter {
  const _TreeConnectorPainter({
    required this.rects,
    required this.childrenById,
  });

  final Map<String, Rect> rects;
  final Map<String, List<_LinkedDocument>> childrenById;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke;
    for (final entry in childrenById.entries) {
      final parent = rects[entry.key];
      if (parent == null) continue;
      final children = entry.value
          .map((document) => rects[document.id])
          .whereType<Rect>()
          .toList(growable: false);
      if (children.isEmpty) continue;
      final start = Offset(parent.center.dx, parent.bottom);
      final branchY = (parent.bottom + children.first.top) / 2;
      if (children.length == 1) {
        final child = children.single;
        final end = Offset(child.center.dx, child.top);
        if ((start.dx - end.dx).abs() < 0.5) {
          canvas.drawLine(start, Offset(end.dx, end.dy - 7), paint);
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(start.dx, branchY)
              ..lineTo(end.dx, branchY)
              ..lineTo(end.dx, end.dy - 7),
            paint,
          );
        }
        _drawArrow(canvas, paint, end);
        continue;
      }

      final childCenters = children.map((child) => child.center.dx);
      final left = childCenters.reduce(math.min);
      final right = childCenters.reduce(math.max);
      canvas.drawLine(start, Offset(start.dx, branchY), paint);
      canvas.drawLine(Offset(left, branchY), Offset(right, branchY), paint);
      for (final child in children) {
        final end = Offset(child.center.dx, child.top);
        canvas.drawLine(
          Offset(end.dx, branchY),
          Offset(end.dx, end.dy - 7),
          paint,
        );
        _drawArrow(canvas, paint, end);
      }
    }
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset end) {
    canvas.drawLine(
      Offset(end.dx - 4, end.dy - 12),
      Offset(end.dx, end.dy - 7),
      paint,
    );
    canvas.drawLine(
      Offset(end.dx + 4, end.dy - 12),
      Offset(end.dx, end.dy - 7),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TreeConnectorPainter oldDelegate) =>
      oldDelegate.rects != rects || oldDelegate.childrenById != childrenById;
}

class _TreeDocumentCard extends StatelessWidget {
  const _TreeDocumentCard({
    required this.document,
    required this.displayStatuses,
    required this.locale,
    required this.strings,
    required this.onTap,
  });

  final _LinkedDocument document;
  final List<_DocumentDisplayStatus> displayStatuses;
  final String locale;
  final _LinkedDocumentStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visibleStatuses = document.isCancellationReceipt || document.isCredit
        ? const <_DocumentDisplayStatus>[]
        : displayStatuses
              .where(
                (status) =>
                    !(document.isReceipt &&
                        status == _DocumentDisplayStatus.paid),
              )
              .toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCAE2F7), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DocumentIcon(document: document, size: 40),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.title(strings),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF172033),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatDate(document.date),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
              const Spacer(),
              Text(
                _formatMoney(document.amount.abs(), locale),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (visibleStatuses.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    for (final status in visibleStatuses)
                      _DocumentStatusPill(status: status, strings: strings),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StandaloneCard extends StatelessWidget {
  const _StandaloneCard({
    required this.count,
    required this.strings,
    required this.onTap,
  });

  final int count;
  final _LinkedDocumentStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE8F4)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.standalone,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    strings.documentCount(count),
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _StandaloneDocumentsPage extends StatelessWidget {
  const _StandaloneDocumentsPage({
    required this.documents,
    required this.userId,
    required this.locale,
  });

  final List<_LinkedDocument> documents;
  final String userId;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final strings = _LinkedDocumentStrings(locale);
    final sorted = [...documents]..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          strings.standalone,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final document = sorted[index];
          return _StandaloneDocumentTile(
            document: document,
            locale: locale,
            strings: strings,
            onTap: () => LinkedDocumentActionService.show(
              context: context,
              userId: userId,
              documentId: document.id,
              documentData: document.data,
              locale: locale,
            ),
          );
        },
      ),
    );
  }
}

class _StandaloneDocumentTile extends StatelessWidget {
  const _StandaloneDocumentTile({
    required this.document,
    required this.locale,
    required this.strings,
    required this.onTap,
  });

  final _LinkedDocument document;
  final String locale;
  final _LinkedDocumentStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFDCE8F4)),
    ),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      leading: _DocumentIcon(document: document, size: 44),
      title: Text(
        document.title(strings),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(_formatDate(document.date)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatMoney(document.amount.abs(), locale),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.strings});

  final _ChainStatus status;
  final _LinkedDocumentStrings strings;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (status) {
      _ChainStatus.open => (
        strings.open,
        const Color(0xFFB45309),
        const Color(0xFFFFEDD5),
      ),
      _ChainStatus.partiallyPaid => (
        strings.partiallyPaid,
        const Color(0xFF1976D2),
        const Color(0xFFDBEAFE),
      ),
      _ChainStatus.partiallyCancelled => (
        strings.partiallyCancelled,
        const Color(0xFFB45309),
        const Color(0xFFFFEDD5),
      ),
      _ChainStatus.completed => (
        strings.completed,
        const Color(0xFF047857),
        const Color(0xFFD1FAE5),
      ),
      _ChainStatus.cancelled => (
        strings.cancelled,
        const Color(0xFFDC2626),
        const Color(0xFFFEE2E2),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DocumentStatusPill extends StatelessWidget {
  const _DocumentStatusPill({required this.status, required this.strings});

  final _DocumentDisplayStatus status;
  final _LinkedDocumentStrings strings;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (status) {
      _DocumentDisplayStatus.paid => (
        strings.paid,
        const Color(0xFF047857),
        const Color(0xFFD1FAE5),
      ),
      _DocumentDisplayStatus.partial => (
        strings.partiallyPaid,
        const Color(0xFF1976D2),
        const Color(0xFFDBEAFE),
      ),
      _DocumentDisplayStatus.partiallyCancelled => (
        strings.partiallyCancelled,
        const Color(0xFFB45309),
        const Color(0xFFFFEDD5),
      ),
      _DocumentDisplayStatus.cancelled => (
        strings.cancelled,
        const Color(0xFFDC2626),
        const Color(0xFFFEE2E2),
      ),
      _DocumentDisplayStatus.accepted => (
        strings.accepted,
        const Color(0xFF047857),
        const Color(0xFFD1FAE5),
      ),
      _DocumentDisplayStatus.open => (
        strings.open,
        const Color(0xFFB45309),
        const Color(0xFFFFEDD5),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DocumentIcon extends StatelessWidget {
  const _DocumentIcon({required this.document, required this.size});

  final _LinkedDocument document;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, foreground, background) = document.isCancellationReceipt
        ? (Icons.undo_rounded, const Color(0xFFDC2626), const Color(0xFFFEE2E2))
        : switch (document.type) {
            'quote' => (
              Icons.description_outlined,
              const Color(0xFF1687F8),
              const Color(0xFFDBEAFE),
            ),
            'work_order' => (
              Icons.build_outlined,
              const Color(0xFFF97316),
              const Color(0xFFFFE7D6),
            ),
            'receipt' => (
              Icons.receipt_outlined,
              const Color(0xFF059669),
              const Color(0xFFD1FAE5),
            ),
            'credit_note' => (
              Icons.undo_rounded,
              const Color(0xFFDC2626),
              const Color(0xFFFEE2E2),
            ),
            _ => (
              Icons.receipt_long_outlined,
              const Color(0xFF7C3AED),
              const Color(0xFFEDE9FE),
            ),
          };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(icon, color: foreground, size: size * 0.55),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), height: 1.45),
          ),
        ],
      ),
    ),
  );
}

enum _DocumentDisplayStatus {
  open,
  partial,
  paid,
  accepted,
  partiallyCancelled,
  cancelled,
}

class _LinkedDocument {
  const _LinkedDocument({
    required this.id,
    required this.type,
    required this.number,
    required this.name,
    required this.amount,
    required this.paidAmount,
    required this.date,
    required this.sourceIds,
    required this.data,
  });

  factory _LinkedDocument.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final sourceIds = <String>{};
    final rawIds = data['linkedDocumentIds'];
    if (rawIds is Iterable) {
      sourceIds.addAll(
        rawIds
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final rawLinks = data['linkedDocuments'];
    if (rawLinks is Iterable) {
      for (final rawLink in rawLinks) {
        if (rawLink is! Map) continue;
        final id = (rawLink['invoiceDocId'] ?? rawLink['id'] ?? '')
            .toString()
            .trim();
        if (id.isNotEmpty) sourceIds.add(id);
      }
    }
    for (final key in ['sourceInvoiceDocId', 'cancellationSourceDocumentId']) {
      final id = (data[key] ?? '').toString().trim();
      if (id.isNotEmpty) sourceIds.add(id);
    }
    final rawDate = data['createdAt'] ?? data['timestamp'];
    final date = rawDate is Timestamp
        ? rawDate.toDate()
        : _parseDocumentDate((data['date'] ?? '').toString());
    return _LinkedDocument(
      id: snapshot.id,
      type: (data['docType'] ?? data['type'] ?? '').toString().trim(),
      number: (data['invoiceNumber'] ?? data['documentNumber'] ?? '')
          .toString()
          .trim(),
      name: (data['name'] ?? '').toString().trim(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0,
      date: date,
      sourceIds: sourceIds,
      data: data,
    );
  }

  final String id;
  final String type;
  final String number;
  final String name;
  final double amount;
  final double paidAmount;
  final DateTime date;
  final Set<String> sourceIds;
  final Map<String, dynamic> data;

  bool get isCredit => type == 'credit_note';
  bool get isReceipt => type == 'receipt';
  bool get isCancellationReceipt =>
      isReceipt && data['isCancellationDocument'] == true;
  bool get isInvoice => type == 'invoice' || type == 'invoice_receipt';
  bool get isCancelled =>
      isCredit ||
      data['isCancellationDocument'] == true ||
      (data['cancellationStatus'] ?? '').toString() == 'cancelled' ||
      (data['documentStatus'] ?? '').toString() == 'cancelled';

  _DocumentDisplayStatus get displayStatus {
    if (isCancelled) return _DocumentDisplayStatus.cancelled;
    final paymentStatus = (data['paymentStatus'] ?? '')
        .toString()
        .toLowerCase();
    if (paymentStatus == 'paid' || type == 'invoice_receipt' || isReceipt) {
      return _DocumentDisplayStatus.paid;
    }
    if (paymentStatus == 'partially_paid' || paidAmount > 0) {
      return _DocumentDisplayStatus.partial;
    }
    if (type == 'quote') return _DocumentDisplayStatus.accepted;
    return _DocumentDisplayStatus.open;
  }

  String title(_LinkedDocumentStrings strings) =>
      '${isCancellationReceipt ? strings.cancelledReceipt : strings.typeName(type)}'
      '${number.isEmpty ? '' : ' #$number'}';
}

class _DocumentGraph {
  const _DocumentGraph({required this.chains, required this.standalone});

  factory _DocumentGraph.fromDocuments(List<_LinkedDocument> documents) {
    final byId = {for (final document in documents) document.id: document};
    final neighbors = {
      for (final document in documents) document.id: <String>{},
    };
    final children = {
      for (final document in documents) document.id: <String>{},
    };
    for (final document in documents) {
      for (final sourceId in document.sourceIds) {
        if (!byId.containsKey(sourceId) || sourceId == document.id) continue;
        neighbors[document.id]!.add(sourceId);
        neighbors[sourceId]!.add(document.id);
        children[sourceId]!.add(document.id);
      }
    }

    final chains = <_DocumentChain>[];
    final standalone = <_LinkedDocument>[];
    final visited = <String>{};
    for (final document in documents) {
      if (!visited.add(document.id)) continue;
      if (neighbors[document.id]!.isEmpty) {
        standalone.add(document);
        continue;
      }
      final componentIds = <String>{document.id};
      final queue = <String>[document.id];
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        for (final neighbor in neighbors[current]!) {
          if (visited.add(neighbor)) {
            componentIds.add(neighbor);
            queue.add(neighbor);
          }
        }
      }
      final componentDocuments = componentIds.map((id) => byId[id]!).toList();
      chains.add(
        _DocumentChain(
          documents: componentDocuments,
          childrenById: {
            for (final id in componentIds)
              id: children[id]!
                  .where(componentIds.contains)
                  .map((childId) => byId[childId]!)
                  .toList(growable: false),
          },
        ),
      );
    }
    chains.sort((a, b) => b.date.compareTo(a.date));
    standalone.sort((a, b) => b.date.compareTo(a.date));
    return _DocumentGraph(chains: chains, standalone: standalone);
  }

  final List<_DocumentChain> chains;
  final List<_LinkedDocument> standalone;

  int get openCount => chains
      .where(
        (chain) =>
            chain.status == _ChainStatus.open ||
            chain.status == _ChainStatus.partiallyPaid ||
            chain.status == _ChainStatus.partiallyCancelled,
      )
      .length;
  int get paidCount =>
      chains.where((chain) => chain.status == _ChainStatus.completed).length;
  int get cancelledCount =>
      chains.where((chain) => chain.status == _ChainStatus.cancelled).length;
}

class _DocumentChain {
  const _DocumentChain({required this.documents, required this.childrenById});

  final List<_LinkedDocument> documents;
  final Map<String, List<_LinkedDocument>> childrenById;

  List<_DocumentDisplayStatus> displayStatusesFor(_LinkedDocument document) {
    if (document.isReceipt && !document.isCancellationReceipt) {
      final cancelledAmount =
          (childrenById[document.id] ?? const <_LinkedDocument>[])
              .where((child) => child.isCancellationReceipt)
              .fold<double>(
                0,
                (cancelledTotal, child) => cancelledTotal + child.amount.abs(),
              );
      final receiptAmount = document.amount.abs();
      if (receiptAmount > 0 && cancelledAmount >= receiptAmount - 0.005) {
        return const [_DocumentDisplayStatus.cancelled];
      }
      if (cancelledAmount > 0.005) {
        return const [_DocumentDisplayStatus.partiallyCancelled];
      }
    }
    if (document.isInvoice) {
      final descendants = _descendantsOf(document);
      final creditDocumentsTotal = descendants
          .where((child) => child.isCredit)
          .fold<double>(
            0,
            (creditTotal, child) => creditTotal + child.amount.abs(),
          );
      final recordedCredit =
          (document.data['cancelledAmount'] as num?)?.toDouble().abs() ?? 0;
      final creditedAmount = math.max(creditDocumentsTotal, recordedCredit);
      final invoiceAmount = document.amount.abs();
      final netInvoiceAmount = math.max(0, invoiceAmount - creditedAmount);
      final cancellationStatus =
          invoiceAmount > 0 && creditedAmount >= invoiceAmount - 0.005
          ? _DocumentDisplayStatus.cancelled
          : creditedAmount > 0.005
          ? _DocumentDisplayStatus.partiallyCancelled
          : null;

      final linkedReceipts = descendants
          .where((child) => child.isReceipt)
          .toList(growable: false);
      final linkedReceiptTotal = linkedReceipts.fold<double>(
        0,
        (receiptTotal, child) => receiptTotal + child.amount,
      );
      final recordedPaidAmount = document.paidAmount.abs();
      final paidAmount = math.max(
        0,
        document.type == 'invoice_receipt'
            ? invoiceAmount + linkedReceiptTotal
            : linkedReceipts.isNotEmpty
            ? linkedReceiptTotal
            : recordedPaidAmount,
      );
      final paymentStatus = netInvoiceAmount <= 0.005
          ? null
          : paidAmount >= netInvoiceAmount - 0.005
          ? _DocumentDisplayStatus.paid
          : paidAmount > 0.005
          ? _DocumentDisplayStatus.partial
          : _DocumentDisplayStatus.open;
      return [?cancellationStatus, ?paymentStatus];
    }
    return [document.displayStatus];
  }

  List<_LinkedDocument> _descendantsOf(_LinkedDocument document) {
    final descendants = <_LinkedDocument>[];
    final seen = <String>{document.id};
    final pending = <_LinkedDocument>[
      ...(childrenById[document.id] ?? const <_LinkedDocument>[]),
    ];
    while (pending.isNotEmpty) {
      final child = pending.removeLast();
      if (!seen.add(child.id)) continue;
      descendants.add(child);
      pending.addAll(childrenById[child.id] ?? const <_LinkedDocument>[]);
    }
    return descendants;
  }

  DateTime get date => documents
      .map((document) => document.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  DateTime get createdDate => documents
      .map((document) => document.date)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  double get _grossTotal {
    final billable = documents.where((document) => document.isInvoice).toList();
    if (billable.isNotEmpty) {
      return billable.fold(
        0,
        (totalAmount, document) => totalAmount + document.amount.abs(),
      );
    }
    final candidates = documents
        .where((document) => !document.isReceipt && !document.isCredit)
        .map((document) => document.amount.abs());
    return candidates.isEmpty ? 0 : candidates.reduce(math.max);
  }

  double get total => cancellation.netInvoiceAmount(_grossTotal);

  double get paid {
    final receipts = documents
        .where((document) => document.isReceipt)
        .fold<double>(
          0,
          // Cancellation receipts are stored with a negative amount and must
          // reduce the paid total instead of being counted as another payment.
          (totalPaid, document) => totalPaid + document.amount,
        );
    final combined = documents
        .where((document) => document.type == 'invoice_receipt')
        .fold<double>(
          0,
          (totalPaid, document) => totalPaid + document.amount.abs(),
        );
    if (receipts + combined != 0) {
      return math.min(total, math.max(0, receipts + combined));
    }
    final recorded = documents
        .where((document) => document.type == 'invoice')
        .fold<double>(
          0,
          (totalPaid, document) => totalPaid + document.paidAmount.abs(),
        );
    return math.min(total, recorded);
  }

  DocumentChainCancellation get cancellation =>
      DocumentChainCancellation.calculate(
        invoiceTotal: _grossTotal,
        creditNoteAmounts: documents
            .where((document) => document.isCredit)
            .map((document) => document.amount),
        recordedCancelledAmounts: documents
            .where((document) => document.isInvoice)
            .map(
              (document) =>
                  (document.data['cancelledAmount'] as num?)?.toDouble() ?? 0,
            ),
      );

  double get remaining => math.max(0, total - paid);

  _ChainStatus get status {
    if (cancellation.status == DocumentChainCancellationStatus.full) {
      return _ChainStatus.cancelled;
    }
    if (cancellation.status == DocumentChainCancellationStatus.partial) {
      return _ChainStatus.partiallyCancelled;
    }
    if (total > 0 && remaining <= 0.005) return _ChainStatus.completed;
    if (paid > 0) return _ChainStatus.partiallyPaid;
    return _ChainStatus.open;
  }

  bool matches(String query, _LinkedDocumentStrings strings) => documents.any(
    (document) =>
        document.number.toLowerCase().contains(query) ||
        document.name.toLowerCase().contains(query) ||
        strings.typeName(document.type).toLowerCase().contains(query),
  );

  List<List<_LinkedDocument>> get levels {
    final childIds = childrenById.values
        .expand((children) => children)
        .map((document) => document.id)
        .toSet();
    var current = documents
        .where((document) => !childIds.contains(document.id))
        .toList();
    if (current.isEmpty) current = [documents.first];
    final result = <List<_LinkedDocument>>[];
    final seen = <String>{};
    while (current.isNotEmpty) {
      current.sort((a, b) => a.date.compareTo(b.date));
      result.add(current);
      seen.addAll(current.map((document) => document.id));
      current = current
          .expand(
            (document) =>
                childrenById[document.id] ?? const <_LinkedDocument>[],
          )
          .where((document) => !seen.contains(document.id))
          .toSet()
          .toList();
    }
    final unseen = documents
        .where((document) => !seen.contains(document.id))
        .toList();
    if (unseen.isNotEmpty) result.add(unseen);
    return result;
  }

  List<List<_LinkedDocument>> get stages => levels;
}

DateTime _parseDocumentDate(String raw) {
  final value = raw.trim();
  final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
  if (compact != null) {
    return DateTime(
      int.parse(compact.group(1)!),
      int.parse(compact.group(2)!),
      int.parse(compact.group(3)!),
    );
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  final display = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value);
  if (display != null) {
    return DateTime(
      int.parse(display.group(3)!),
      int.parse(display.group(2)!),
      int.parse(display.group(1)!),
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _formatDate(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) return '—';
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String _formatMoney(double amount, String locale) =>
    '${intl.NumberFormat('#,##0.00', _numberLocale(locale)).format(amount)} ₪';

String _numberLocale(String locale) => switch (locale) {
  'he' => 'he_IL',
  'ar' => 'ar',
  'ru' => 'ru',
  'am' => 'am',
  _ => 'en_US',
};

class _LinkedDocumentStrings {
  _LinkedDocumentStrings(String locale)
    : values = _values[locale] ?? _values['en']!;

  final Map<String, String> values;
  String get title => values['title']!;
  String get subtitle => values['subtitle']!;
  String get searchHint => values['searchHint']!;
  String get all => values['all']!;
  String get open => values['open']!;
  String get paid => values['paid']!;
  String get cancelled => values['cancelled']!;
  String get partiallyPaid => values['partiallyPaid']!;
  String get partiallyCancelled => values['partiallyCancelled']!;
  String get cancelledReceipt => values['cancelledReceipt']!;
  String get completed => values['completed']!;
  String get accepted => values['accepted']!;
  String get sort => values['sort']!;
  String get newest => values['newest']!;
  String get oldest => values['oldest']!;
  String get highestAmount => values['highestAmount']!;
  String get chain => values['chain']!;
  String get standalone => values['standalone']!;
  String get totalAmount => values['totalAmount']!;
  String get paidAmount => values['paidAmount']!;
  String get remaining => values['remaining']!;
  String get created => values['created']!;
  String get more => values['more']!;
  String get clear => values['clear']!;
  String get signIn => values['signIn']!;
  String get signInMessage => values['signInMessage']!;
  String get loadFailed => values['loadFailed']!;
  String get tryAgain => values['tryAgain']!;
  String get noDocuments => values['noDocuments']!;
  String get noDocumentsMessage => values['noDocumentsMessage']!;
  String get noResults => values['noResults']!;
  String get noResultsMessage => values['noResultsMessage']!;
  String documentCount(int count) =>
      '$count ${count == 1 ? values['document'] : values['documents']}';

  String typeName(String type) => switch (type) {
    'quote' => values['quote']!,
    'work_order' => values['workOrder']!,
    'transaction_account' => values['transactionAccount']!,
    'invoice' => values['invoice']!,
    'invoice_receipt' => values['invoiceReceipt']!,
    'receipt' => values['receipt']!,
    'credit_note' => values['creditNote']!,
    _ => values['document']!,
  };

  String pluralTypeName(String type) => typeName(type);

  static const _values = <String, Map<String, String>>{
    'en': {
      'title': 'Linked Documents',
      'subtitle': 'All documents for this client, grouped by chains',
      'searchHint': 'Search by document number...',
      'all': 'All',
      'open': 'Open',
      'paid': 'Paid',
      'cancelled': 'Cancelled',
      'partiallyPaid': 'Partially paid',
      'partiallyCancelled': 'Partially cancelled',
      'cancelledReceipt': 'Cancelled receipt',
      'completed': 'Completed',
      'accepted': 'Accepted',
      'sort': 'Sort and filter',
      'sortBy': 'Sort by',
      'newest': 'Newest',
      'oldest': 'Oldest',
      'highestAmount': 'Highest amount',
      'groupByChains': 'Group by: Chains',
      'chain': 'Chain',
      'standalone': 'Standalone documents',
      'totalAmount': 'Total amount',
      'paidAmount': 'Paid',
      'remaining': 'Remaining',
      'created': 'Created',
      'more': 'More',
      'clear': 'Clear search',
      'openingDocument': 'Opening document...',
      'openFailed': 'Could not open this document.',
      'signIn': 'Sign in required',
      'signInMessage': 'Sign in to view linked documents.',
      'loadFailed': 'Could not load documents',
      'tryAgain': 'Check your connection and try again.',
      'noDocuments': 'No documents yet',
      'noDocumentsMessage':
          'Documents created for this client will appear here.',
      'noResults': 'No matching chains',
      'noResultsMessage': 'Try another search or filter.',
      'document': 'document',
      'documents': 'documents',
      'quote': 'Quote',
      'workOrder': 'Work order',
      'transactionAccount': 'Transaction account',
      'invoice': 'Invoice',
      'invoiceReceipt': 'Invoice / receipt',
      'receipt': 'Receipt',
      'creditNote': 'Credit invoice',
    },
    'he': {
      'title': 'מסמכים מקושרים',
      'subtitle': 'כל מסמכי הלקוח, מקובצים לפי שרשראות',
      'searchHint': 'חיפוש לפי מספר מסמך...',
      'all': 'הכול',
      'open': 'פתוח',
      'paid': 'שולם',
      'cancelled': 'בוטל',
      'partiallyPaid': 'שולם חלקית',
      'partiallyCancelled': 'בוטל חלקית',
      'cancelledReceipt': 'קבלה מבטלת',
      'completed': 'הושלם',
      'accepted': 'אושר',
      'sort': 'מיון וסינון',
      'sortBy': 'מיון',
      'newest': 'החדש ביותר',
      'oldest': 'הישן ביותר',
      'highestAmount': 'הסכום הגבוה',
      'groupByChains': 'קיבוץ: שרשראות',
      'chain': 'שרשרת',
      'standalone': 'מסמכים עצמאיים',
      'totalAmount': 'סכום כולל',
      'paidAmount': 'שולם',
      'remaining': 'נותר',
      'created': 'נוצר',
      'more': 'עוד',
      'clear': 'נקה חיפוש',
      'openingDocument': 'פותח מסמך...',
      'openFailed': 'לא ניתן לפתוח את המסמך.',
      'signIn': 'נדרשת התחברות',
      'signInMessage': 'יש להתחבר כדי לראות מסמכים מקושרים.',
      'loadFailed': 'טעינת המסמכים נכשלה',
      'tryAgain': 'בדוק את החיבור ונסה שוב.',
      'noDocuments': 'אין עדיין מסמכים',
      'noDocumentsMessage': 'מסמכים שייווצרו ללקוח יופיעו כאן.',
      'noResults': 'לא נמצאו שרשראות',
      'noResultsMessage': 'נסה חיפוש או מסנן אחר.',
      'document': 'מסמך',
      'documents': 'מסמכים',
      'quote': 'הצעת מחיר',
      'workOrder': 'הזמנת עבודה',
      'transactionAccount': 'חשבון עסקה',
      'invoice': 'חשבונית מס',
      'invoiceReceipt': 'חשבונית מס / קבלה',
      'receipt': 'קבלה',
      'creditNote': 'חשבונית מס זיכוי',
    },
    'ar': {
      'title': 'المستندات المرتبطة',
      'subtitle': 'كل مستندات العميل مجمعة كسلاسل',
      'searchHint': 'البحث برقم المستند...',
      'all': 'الكل',
      'open': 'مفتوح',
      'paid': 'مدفوع',
      'cancelled': 'ملغى',
      'partiallyPaid': 'مدفوع جزئياً',
      'partiallyCancelled': 'ملغى جزئياً',
      'cancelledReceipt': 'إيصال إلغاء',
      'completed': 'مكتمل',
      'accepted': 'مقبول',
      'sort': 'ترتيب وتصفية',
      'sortBy': 'ترتيب حسب',
      'newest': 'الأحدث',
      'oldest': 'الأقدم',
      'highestAmount': 'أعلى مبلغ',
      'groupByChains': 'التجميع: سلاسل',
      'chain': 'سلسلة',
      'standalone': 'مستندات مستقلة',
      'totalAmount': 'المبلغ الكلي',
      'paidAmount': 'المدفوع',
      'remaining': 'المتبقي',
      'created': 'تاريخ الإنشاء',
      'more': 'المزيد',
      'clear': 'مسح البحث',
      'openingDocument': 'جارٍ فتح المستند...',
      'openFailed': 'تعذر فتح المستند.',
      'signIn': 'تسجيل الدخول مطلوب',
      'signInMessage': 'سجّل الدخول لعرض المستندات المرتبطة.',
      'loadFailed': 'تعذر تحميل المستندات',
      'tryAgain': 'تحقق من الاتصال وحاول مرة أخرى.',
      'noDocuments': 'لا توجد مستندات بعد',
      'noDocumentsMessage': 'ستظهر هنا المستندات المنشأة لهذا العميل.',
      'noResults': 'لا توجد سلاسل مطابقة',
      'noResultsMessage': 'جرّب بحثاً أو مرشحاً آخر.',
      'document': 'مستند',
      'documents': 'مستندات',
      'quote': 'عرض سعر',
      'workOrder': 'أمر عمل',
      'transactionAccount': 'حساب معاملة',
      'invoice': 'فاتورة',
      'invoiceReceipt': 'فاتورة / إيصال',
      'receipt': 'إيصال',
      'creditNote': 'فاتورة دائنة',
    },
    'ru': {
      'title': 'Связанные документы',
      'subtitle': 'Все документы клиента, сгруппированные в цепочки',
      'searchHint': 'Поиск по номеру документа...',
      'all': 'Все',
      'open': 'Открытые',
      'paid': 'Оплачено',
      'cancelled': 'Отменено',
      'partiallyPaid': 'Частично оплачено',
      'partiallyCancelled': 'Частично отменено',
      'cancelledReceipt': 'Отменяющая квитанция',
      'completed': 'Завершено',
      'accepted': 'Принято',
      'sort': 'Сортировка и фильтр',
      'sortBy': 'Сортировка',
      'newest': 'Сначала новые',
      'oldest': 'Сначала старые',
      'highestAmount': 'По сумме',
      'groupByChains': 'Группировка: цепочки',
      'chain': 'Цепочка',
      'standalone': 'Отдельные документы',
      'totalAmount': 'Общая сумма',
      'paidAmount': 'Оплачено',
      'remaining': 'Остаток',
      'created': 'Создано',
      'more': 'Ещё',
      'clear': 'Очистить поиск',
      'openingDocument': 'Открытие документа...',
      'openFailed': 'Не удалось открыть документ.',
      'signIn': 'Требуется вход',
      'signInMessage': 'Войдите для просмотра связанных документов.',
      'loadFailed': 'Не удалось загрузить документы',
      'tryAgain': 'Проверьте соединение и повторите.',
      'noDocuments': 'Документов пока нет',
      'noDocumentsMessage': 'Документы этого клиента появятся здесь.',
      'noResults': 'Цепочки не найдены',
      'noResultsMessage': 'Измените поиск или фильтр.',
      'document': 'документ',
      'documents': 'документов',
      'quote': 'Предложение',
      'workOrder': 'Заказ на работу',
      'transactionAccount': 'Счёт сделки',
      'invoice': 'Счёт',
      'invoiceReceipt': 'Счёт / квитанция',
      'receipt': 'Квитанция',
      'creditNote': 'Кредитовый счёт',
    },
    'am': {
      'title': 'የተገናኙ ሰነዶች',
      'subtitle': 'የደንበኛው ሰነዶች በሰንሰለት ተመድበው',
      'searchHint': 'በሰነድ ቁጥር ይፈልጉ...',
      'all': 'ሁሉም',
      'open': 'ክፍት',
      'paid': 'ተከፍሏል',
      'cancelled': 'ተሰርዟል',
      'partiallyPaid': 'በከፊል ተከፍሏል',
      'partiallyCancelled': 'በከፊል ተሰርዟል',
      'cancelledReceipt': 'የተሰረዘ ደረሰኝ',
      'completed': 'ተጠናቋል',
      'accepted': 'ጸድቋል',
      'sort': 'ደርድር እና አጣራ',
      'sortBy': 'ደርድር',
      'newest': 'አዲስ መጀመሪያ',
      'oldest': 'የቆየ መጀመሪያ',
      'highestAmount': 'ከፍተኛ መጠን',
      'groupByChains': 'ቡድን: ሰንሰለቶች',
      'chain': 'ሰንሰለት',
      'standalone': 'ብቻቸውን ያሉ ሰነዶች',
      'totalAmount': 'ጠቅላላ መጠን',
      'paidAmount': 'የተከፈለ',
      'remaining': 'ቀሪ',
      'created': 'የተፈጠረ',
      'more': 'ተጨማሪ',
      'clear': 'ፍለጋ አጽዳ',
      'openingDocument': 'ሰነድ በመክፈት ላይ...',
      'openFailed': 'ሰነዱን መክፈት አልተቻለም።',
      'signIn': 'መግባት ያስፈልጋል',
      'signInMessage': 'የተገናኙ ሰነዶችን ለማየት ይግቡ።',
      'loadFailed': 'ሰነዶችን መጫን አልተቻለም',
      'tryAgain': 'ግንኙነትዎን ይፈትሹና ይሞክሩ።',
      'noDocuments': 'እስካሁን ሰነድ የለም',
      'noDocumentsMessage': 'ለዚህ ደንበኛ የሚፈጠሩ ሰነዶች እዚህ ይታያሉ።',
      'noResults': 'ተዛማጅ ሰንሰለት የለም',
      'noResultsMessage': 'ሌላ ፍለጋ ወይም ማጣሪያ ይሞክሩ።',
      'document': 'ሰነድ',
      'documents': 'ሰነዶች',
      'quote': 'የዋጋ ማቅረቢያ',
      'workOrder': 'የሥራ ትዕዛዝ',
      'transactionAccount': 'የግብይት ሂሳብ',
      'invoice': 'ደረሰኝ',
      'invoiceReceipt': 'ደረሰኝ / ክፍያ',
      'receipt': 'የክፍያ ደረሰኝ',
      'creditNote': 'የብድር ደረሰኝ',
    },
  };
}
