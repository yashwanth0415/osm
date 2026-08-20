(function () {
  'use strict';

  function setupScrollReveals() {
    const candidates = [
      '.section > .section-inner',
      '.section-inner > .section-label',
      '.section-inner > .section-heading',
      '.section-inner > .section-text',
      '.feature-card', '.tech-card', '.process-step',
      '.home-portfolio-card', '.portfolio-view-more',
      '.project-card', '.projects-intro-grid > *', '.featured-project > *', '.tool-card',
      '.blog-card', '.newsletter-card',
      '.story-grid > *', '.mv-card', '.philosophy-card', '.service-summary-card', '.team-card',
      '.contact-info-item', '.contact-form-wrapper',
      '.article-section', '.related-card',
      '.cta-section > *'
    ];

    const nodes = document.querySelectorAll(candidates.join(','));
    nodes.forEach((el, i) => {
      if (el.closest('header, nav, footer, script, style')) return;
      el.classList.add('osm-reveal');
      if (i % 4 === 1) el.classList.add('osm-reveal-delay-1');
      else if (i % 4 === 2) el.classList.add('osm-reveal-delay-2');
      else if (i % 4 === 3) el.classList.add('osm-reveal-delay-3');
    });

    const show = el => el.classList.add('osm-visible');

    if (!('IntersectionObserver' in window)) {
      nodes.forEach(show);
      return;
    }

    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          show(entry.target);
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.08, rootMargin: '0px 0px -6% 0px' });

    nodes.forEach(el => observer.observe(el));
  }

  function setupProjectFilters() {
    const filterBar = document.querySelector('.project-filter');
    const grid = document.getElementById('projectsGrid');
    if (!filterBar || !grid) return;

    const buttons = Array.from(filterBar.querySelectorAll('.filter-btn'));
    const cards = Array.from(grid.querySelectorAll('.project-card'));

    function applyFilter(category) {
      cards.forEach((card, index) => {
        const show = category === 'all' || card.dataset.category === category;
        card.hidden = !show;
        if (show) {
          card.classList.remove('osm-visible');
          requestAnimationFrame(() => requestAnimationFrame(() => card.classList.add('osm-visible')));
        }
      });

      buttons.forEach(btn => btn.classList.toggle('active', btn.dataset.filter === category));
    }

    buttons.forEach(button => {
      button.addEventListener('click', function (event) {
        event.preventDefault();
        applyFilter(button.dataset.filter || 'all');
      });
    });

    applyFilter('all');
  }

  function init() {
    setupScrollReveals();
    setupProjectFilters();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
