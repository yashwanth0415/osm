/**
 * Client-side partial loader for header.html and footer.html
 * Loads shared header/footer into placeholder elements
 */
(function() {
    'use strict';

    async function loadPartial(selector, url) {
        const placeholder = document.querySelector(selector);
        if (!placeholder) return;

        try {
            const response = await fetch(url + '?v=' + Date.now(), {
                cache: 'no-store'
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const html = await response.text();
            placeholder.outerHTML = html;

            // Re-initialize mobile menu after header loads
            if (selector === 'header-include') {
                initMobileMenu();
            }
        } catch (err) {
            console.error(`Failed to load ${url}:`, err);
            placeholder.outerHTML = `<!-- Failed to load ${url} -->`;
        }
    }

    function initMobileMenu() {
        const mobileToggle = document.getElementById('mobileToggle');
        const mobileMenu = document.getElementById('mobileMenu');

        if (!mobileToggle || !mobileMenu) return;

        // Remove any existing listeners by cloning
        const newToggle = mobileToggle.cloneNode(true);
        mobileToggle.parentNode.replaceChild(newToggle, mobileToggle);

        newToggle.addEventListener('click', () => {
            mobileMenu.classList.toggle('open');
            const spans = newToggle.querySelectorAll('span');
            if (mobileMenu.classList.contains('open')) {
                spans[0].style.transform = 'rotate(45deg) translate(6px,6px)';
                spans[1].style.opacity = '0';
                spans[2].style.transform = 'rotate(-45deg) translate(6px,-6px)';
            } else {
                spans[0].style.transform = '';
                spans[1].style.opacity = '';
                spans[2].style.transform = '';
            }
        });

        // Close menu function for inline onclick
        window.closeMobileMenu = function() {
            mobileMenu.classList.remove('open');
            const spans = newToggle.querySelectorAll('span');
            spans[0].style.transform = '';
            spans[1].style.opacity = '';
            spans[2].style.transform = '';
        };
    }

    // Load header and footer
    document.addEventListener('DOMContentLoaded', () => {
        loadPartial('header-include', 'header.html');
        loadPartial('footer-include', 'footer.html');
    });
})();