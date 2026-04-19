const samsarService = require('../../../../services/samsar');

module.exports = {
    async enhanceText(req, res, next) {
        try {
            const message = typeof req.body?.message === 'string' ? req.body.message.trim() : '';
            const language = typeof req.body?.language === 'string' ? req.body.language.trim() : undefined;
            const maxWords = Number.isFinite(Number(req.body?.maxWords)) ? Number(req.body.maxWords) : undefined;

            if (!message) {
                return res.status(400).json({
                    errors: [{
                        message: 'message is required'
                    }]
                });
            }

            const result = await samsarService.enhanceText({
                message,
                language,
                maxWords,
                metadata: {
                    source: 'samsar-blog-admin',
                    route: 'ghost/api/admin/samsar/enhance-text'
                }
            });

            return res.json({
                content: result.content || ''
            });
        } catch (error) {
            return next(error);
        }
    }
};
