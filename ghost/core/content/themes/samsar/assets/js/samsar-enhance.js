document.addEventListener('DOMContentLoaded', () => {
    const root = document.querySelector('[data-enhance-root]');

    if (!root) {
        return;
    }

    const input = root.querySelector('[data-enhance-input]');
    const language = root.querySelector('[data-enhance-language]');
    const maxWords = root.querySelector('[data-enhance-maxwords]');
    const submit = root.querySelector('[data-enhance-submit]');
    const status = root.querySelector('[data-enhance-status]');
    const output = root.querySelector('[data-enhance-output]');

    submit.addEventListener('click', async () => {
        const message = input.value.trim();

        if (!message) {
            status.textContent = 'Enter text to enhance.';
            return;
        }

        submit.disabled = true;
        status.textContent = 'Enhancing...';
        output.hidden = true;

        try {
            const response = await fetch('/members/api/samsar/enhance-text', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    message,
                    language: language.value.trim() || undefined,
                    maxWords: maxWords.value ? Number(maxWords.value) : undefined
                })
            });

            const payload = await response.json();

            if (!response.ok) {
                throw new Error(payload?.errors?.[0]?.message || 'Enhancement failed');
            }

            output.textContent = payload.content || '';
            output.hidden = false;
            status.textContent = 'Enhanced text ready.';
        } catch (error) {
            status.textContent = error.message || 'Enhancement failed';
        } finally {
            submit.disabled = false;
        }
    });
});
