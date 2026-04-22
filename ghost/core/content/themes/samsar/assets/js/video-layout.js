(function () {
    const CARD_SELECTOR = '.kg-video-card, .kg-embed-card';
    const RESPONSIVE_CLASS = 'kg-samsar-responsive-video';
    const MEDIA_CLASS = 'kg-samsar-responsive-video-media';
    const PORTRAIT_MAX_WIDTH = 420;
    const SQUARE_MAX_WIDTH = 560;
    const LANDSCAPE_FULL_WIDTH = 720;
    const VIDEO_HOST_PATTERN = /(youtube(?:-nocookie)?\.com|youtu\.be|vimeo\.com|player\.vimeo\.com|tiktok\.com|loom\.com|wistia\.(?:com|net)|streamable\.com|dailymotion\.com|twitch\.tv|instagram\.com|facebook\.com)/i;

    function toDimension(value) {
        const number = Number.parseFloat(value);
        return Number.isFinite(number) && number > 0 ? number : null;
    }

    function isVideoMedia(media, card) {
        if (!media) {
            return false;
        }

        if (media.tagName === 'VIDEO' || card.classList.contains('kg-video-card')) {
            return true;
        }

        const src = media.getAttribute('src') || '';
        return VIDEO_HOST_PATTERN.test(src);
    }

    function getMedia(card) {
        return card.classList.contains('kg-video-card')
            ? card.querySelector('.kg-video-container video')
            : card.querySelector('iframe, video');
    }

    function getDimensions(media) {
        const width = toDimension(media.videoWidth) || toDimension(media.getAttribute('width')) || toDimension(media.width);
        const height = toDimension(media.videoHeight) || toDimension(media.getAttribute('height')) || toDimension(media.height);

        if (!width || !height) {
            return null;
        }

        return {width, height};
    }

    function getOrientation(width, height) {
        const ratio = width / height;

        if (ratio < 0.9) {
            return 'portrait';
        }

        if (ratio <= 1.2) {
            return 'square';
        }

        return 'landscape';
    }

    function getMaxWidth(width, height, media) {
        const orientation = getOrientation(width, height);

        if (orientation === 'portrait') {
            if (media.tagName === 'IFRAME') {
                return `${PORTRAIT_MAX_WIDTH}px`;
            }

            return `${Math.min(width, PORTRAIT_MAX_WIDTH)}px`;
        }

        if (orientation === 'square') {
            return `${Math.min(width, SQUARE_MAX_WIDTH)}px`;
        }

        if (media.tagName === 'IFRAME' || width >= LANDSCAPE_FULL_WIDTH) {
            return '100%';
        }

        return `${width}px`;
    }

    function applyCardLayout(card) {
        const media = getMedia(card);

        if (!isVideoMedia(media, card)) {
            return;
        }

        if (media.tagName === 'VIDEO' && !media.dataset.samsarResponsiveVideoBound) {
            media.dataset.samsarResponsiveVideoBound = 'true';
            media.addEventListener('loadedmetadata', () => applyCardLayout(card), {once: true});
        }

        const dimensions = getDimensions(media);

        if (!dimensions) {
            return;
        }

        const {width, height} = dimensions;
        const orientation = getOrientation(width, height);

        card.classList.add(RESPONSIVE_CLASS);
        media.classList.add(MEDIA_CLASS);
        card.style.setProperty('--kg-samsar-video-aspect-ratio', `${width} / ${height}`);
        card.style.setProperty('--kg-samsar-video-max-width', getMaxWidth(width, height, media));
        card.dataset.samsarVideoWidth = String(Math.round(width));
        card.dataset.samsarVideoHeight = String(Math.round(height));
        card.dataset.samsarVideoOrientation = orientation;
    }

    function applyLayouts(root) {
        root.querySelectorAll(CARD_SELECTOR).forEach(applyCardLayout);
    }

    function scheduleApply(root) {
        window.requestAnimationFrame(() => applyLayouts(root));
    }

    function init() {
        applyLayouts(document);

        const observer = new MutationObserver(() => scheduleApply(document));
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init, {once: true});
    } else {
        init();
    }
})();
