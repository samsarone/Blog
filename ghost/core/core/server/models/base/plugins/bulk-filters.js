const chunk = require('lodash/chunk');
const nql = require('@tryghost/nql');

const CHUNK_SIZE = 100;

function* byNQL(filter) {
    yield (qb) => {
        nql(filter).querySQL(qb);
    };
}

function* byColumnValues(column, values, chunkSize = CHUNK_SIZE) {
    for (const currentChunk of chunk(values, chunkSize)) {
        yield (qb) => qb.whereIn(column, currentChunk);
    }
}

function* byIds(ids, chunkSize = CHUNK_SIZE) {
    yield* byColumnValues('id', ids, chunkSize);
}

module.exports = {
    CHUNK_SIZE,
    byNQL,
    byColumnValues,
    byIds
};
