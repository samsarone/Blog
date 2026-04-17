const path = require('path');
const {pathToFileURL} = require('url');

class SamsarService {
    async #loadClientClass() {
        const sdkPath = path.resolve(__dirname, '../../../../../../samsar-js/dist/index.js');
        const sdkModule = await import(pathToFileURL(sdkPath).href);

        return sdkModule.default || sdkModule.SamsarClient;
    }

    #getConfig() {
        const apiKey = process.env.API_KEY;

        if (!apiKey) {
            throw new Error('API_KEY is required for Samsar blog integrations.');
        }

        return {
            apiKey,
            baseUrl: process.env.API_HOST || 'https://api.samsar.one/v1'
        };
    }

    async enhanceText({message, language, maxWords, metadata}) {
        const SamsarClient = await this.#loadClientClass();
        const {apiKey, baseUrl} = this.#getConfig();

        const client = new SamsarClient({
            apiKey,
            baseUrl
        });

        const response = await client.enhanceMessage({
            message,
            language,
            maxWords,
            metadata
        });

        return response.data;
    }
}

module.exports = new SamsarService();
