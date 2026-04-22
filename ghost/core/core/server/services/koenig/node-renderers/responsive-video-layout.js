const RESPONSIVE_VIDEO_CLASS = 'kg-samsar-responsive-video';
const RESPONSIVE_VIDEO_MEDIA_CLASS = 'kg-samsar-responsive-video-media';

const PORTRAIT_MAX_WIDTH = 420;
const SQUARE_MAX_WIDTH = 560;
const LANDSCAPE_FULL_WIDTH = 720;

function toDimension(value) {
    const number = Number.parseFloat(value);
    return Number.isFinite(number) && number > 0 ? number : null;
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

function getMaxWidth(width, height, {preferFullLandscape = false, preferMobilePortrait = false} = {}) {
    const orientation = getOrientation(width, height);

    if (orientation === 'portrait') {
        if (preferMobilePortrait) {
            return `${PORTRAIT_MAX_WIDTH}px`;
        }

        return `${Math.min(width, PORTRAIT_MAX_WIDTH)}px`;
    }

    if (orientation === 'square') {
        return `${Math.min(width, SQUARE_MAX_WIDTH)}px`;
    }

    if (preferFullLandscape || width >= LANDSCAPE_FULL_WIDTH) {
        return '100%';
    }

    return `${width}px`;
}

function getResponsiveVideoLayout(widthValue, heightValue, options = {}) {
    const width = toDimension(widthValue);
    const height = toDimension(heightValue);

    if (!width || !height) {
        return null;
    }

    return {
        width,
        height,
        orientation: getOrientation(width, height),
        maxWidth: getMaxWidth(width, height, options),
        aspectRatio: `${width} / ${height}`
    };
}

function getResponsiveVideoStyle(width, height, options = {}) {
    const layout = getResponsiveVideoLayout(width, height, options);

    if (!layout) {
        return '';
    }

    return [
        `--kg-samsar-video-aspect-ratio: ${layout.aspectRatio}`,
        `--kg-samsar-video-max-width: ${layout.maxWidth}`
    ].join('; ');
}

function getResponsiveVideoAttributes(width, height, options = {}) {
    const layout = getResponsiveVideoLayout(width, height, options);

    if (!layout) {
        return {
            className: '',
            attributes: ''
        };
    }

    return {
        className: ` ${RESPONSIVE_VIDEO_CLASS}`,
        attributes: [
            `style="${getResponsiveVideoStyle(width, height, options)}"`,
            `data-samsar-video-width="${Math.round(layout.width)}"`,
            `data-samsar-video-height="${Math.round(layout.height)}"`,
            `data-samsar-video-orientation="${layout.orientation}"`
        ].join(' ')
    };
}

function appendClass(element, className) {
    const existingClass = element.getAttribute('class') || '';

    if (!existingClass.split(/\s+/).includes(className)) {
        element.setAttribute('class', `${existingClass} ${className}`.trim());
    }
}

function appendStyle(element, style) {
    if (!style) {
        return;
    }

    const existingStyle = element.getAttribute('style');
    element.setAttribute('style', existingStyle ? `${existingStyle.replace(/;?\s*$/, ';')} ${style}` : style);
}

function applyResponsiveVideoLayout(element, width, height, options = {}) {
    const layout = getResponsiveVideoLayout(width, height, options);

    if (!layout) {
        return false;
    }

    appendClass(element, RESPONSIVE_VIDEO_CLASS);
    appendStyle(element, getResponsiveVideoStyle(width, height, options));
    element.setAttribute('data-samsar-video-width', String(Math.round(layout.width)));
    element.setAttribute('data-samsar-video-height', String(Math.round(layout.height)));
    element.setAttribute('data-samsar-video-orientation', layout.orientation);

    return true;
}

function applyResponsiveVideoMediaClass(element) {
    if (element) {
        appendClass(element, RESPONSIVE_VIDEO_MEDIA_CLASS);
    }
}

module.exports = {
    RESPONSIVE_VIDEO_CLASS,
    RESPONSIVE_VIDEO_MEDIA_CLASS,
    applyResponsiveVideoLayout,
    applyResponsiveVideoMediaClass,
    getResponsiveVideoAttributes,
    getResponsiveVideoLayout,
    getResponsiveVideoStyle,
    toDimension
};
