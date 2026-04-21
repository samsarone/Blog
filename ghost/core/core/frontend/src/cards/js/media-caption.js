(function() {
    const captionSelector = '.kg-image-card > figcaption, .kg-gallery-card > figcaption, .kg-embed-card > figcaption, .kg-video-card > figcaption';
    const contentClass = 'kg-media-caption-content';
    const toggleClass = 'kg-media-caption-toggle';
    const expandedClass = 'kg-media-caption-expanded';
    const overflowClass = 'kg-media-caption-overflow';

    const getDirectChildByClass = function (element, className) {
        return Array.from(element.children).find(child => child.classList.contains(className));
    };

    const getTwoLineHeight = function (element) {
        const styles = window.getComputedStyle(element);
        const parsedLineHeight = parseFloat(styles.lineHeight);
        const parsedFontSize = parseFloat(styles.fontSize);
        const lineHeight = Number.isFinite(parsedLineHeight)
            ? parsedLineHeight
            : (Number.isFinite(parsedFontSize) ? parsedFontSize * 1.4 : 20);

        return lineHeight * 2;
    };

    const captionHasOverflow = function (content) {
        return content.scrollHeight > getTwoLineHeight(content) + 1;
    };

    const updateOverflowState = function (caption) {
        const content = getDirectChildByClass(caption, contentClass);

        if (!content) {
            return;
        }

        caption.classList.toggle(overflowClass, captionHasOverflow(content));
    };

    const enhanceCaption = function (caption) {
        if (caption.dataset.kgCaption === 'true') {
            updateOverflowState(caption);
            return;
        }

        let content = getDirectChildByClass(caption, contentClass);

        if (!content) {
            content = document.createElement('div');
            content.className = contentClass;

            while (caption.firstChild) {
                content.appendChild(caption.firstChild);
            }

            caption.appendChild(content);
        }

        let toggle = getDirectChildByClass(caption, toggleClass);

        if (!toggle) {
            toggle = document.createElement('button');
            toggle.className = toggleClass;
            toggle.type = 'button';
            caption.appendChild(toggle);
        }

        caption.dataset.kgCaption = 'true';
        caption.classList.add('kg-media-caption');
        toggle.setAttribute('aria-expanded', 'false');
        toggle.textContent = 'View more';

        toggle.addEventListener('click', function (event) {
            event.preventDefault();
            event.stopPropagation();

            const isExpanded = caption.classList.toggle(expandedClass);
            toggle.setAttribute('aria-expanded', isExpanded ? 'true' : 'false');
            toggle.textContent = isExpanded ? 'View less' : 'View more';
        });

        window.requestAnimationFrame(function () {
            updateOverflowState(caption);
        });
    };

    const enhanceCaptions = function (root) {
        if (!root.querySelectorAll) {
            return;
        }

        root.querySelectorAll(captionSelector).forEach(enhanceCaption);
    };

    const updateCaptions = function () {
        document.querySelectorAll(captionSelector).forEach(function (caption) {
            if (caption.dataset.kgCaption === 'true') {
                updateOverflowState(caption);
            }
        });
    };

    enhanceCaptions(document);

    const observer = new MutationObserver(function (mutations) {
        mutations.forEach(function (mutation) {
            mutation.addedNodes.forEach(function (node) {
                if (node.nodeType !== Node.ELEMENT_NODE) {
                    return;
                }

                if (node.matches && node.matches(captionSelector)) {
                    enhanceCaption(node);
                }

                enhanceCaptions(node);
            });
        });
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true
    });

    let resizeFrame = null;
    window.addEventListener('resize', function () {
        if (resizeFrame) {
            window.cancelAnimationFrame(resizeFrame);
        }

        resizeFrame = window.requestAnimationFrame(function () {
            resizeFrame = null;
            updateCaptions();
        });
    });
})();
