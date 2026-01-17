import 'dart:html';

void setupTocObserver() {
  final tocLinks = document.querySelectorAll('.toc a');
  if (tocLinks.isEmpty) return;

  final headings = document.querySelectorAll('h2[id], h3[id], h4[id]');
  if (headings.isEmpty) return;

  String? activeId;

  void setActive(String? id) {
    if (id == activeId) return;
    activeId = id;
    for (final link in tocLinks) {
      final href = link.getAttribute('href');
      final isActive = href != null && (href == '#$id' || href.endsWith('#$id'));
      link.classes.toggle('toc-active', isActive);
    }
  }

  String? idFromHref(String? href) {
    if (href == null) return null;
    final idx = href.lastIndexOf('#');
    if (idx == -1 || idx == href.length - 1) return null;
    return href.substring(idx + 1);
  }

  final observer = IntersectionObserver(
    (entries, _) {
      for (final entry in entries) {
        if (entry.isIntersecting) {
          final id = entry.target.id;
          if (id != null && id.isNotEmpty) {
            setActive(id);
            break;
          }
        }
      }
    },
    {
      'rootMargin': '-40% 0px -40% 0px',
      'threshold': [0, 0.1, 0.5],
    },
  );

  for (final h in headings) {
    observer.observe(h);
  }

  for (final link in tocLinks) {
    link.onClick.listen((_) {
      setActive(idFromHref(link.getAttribute('href')));
    });
  }

  final currentHash = window.location.hash;
  if (currentHash.isNotEmpty) {
    setActive(currentHash.substring(1));
  }

  window.onHashChange.listen((_) {
    final hash = window.location.hash;
    if (hash.isNotEmpty) {
      setActive(hash.substring(1));
    }
  });
}
