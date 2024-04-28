module.exports = {
    content: ["./**/*.{html,svg,sql}", "./static/markdown.html"],
    theme: {
        extend: {
            colors: {
                default: 'var(--color-default)',
                other: 'var(--color-secondary)',
                accent: 'var(--color-accent)',
                primary: 'var(--color-primary)',
                success: 'var(--color-success)',
                danger: 'var(--color-danger)',
            },
            letterSpacing: {
                tighterer: '-0.1em',
            },
        },
    },
    plugins: [
        require('@tailwindcss/typography'),
        require('@tailwindcss/forms'),
        require('@tailwindcss/aspect-ratio'),
    ],
};
