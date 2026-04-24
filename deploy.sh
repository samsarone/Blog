#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

FULL_DEPLOY=0

usage() {
    cat <<'USAGE'
Usage: ./deploy.sh [--all] [--help]

Options:
  --all   Commit local changes, push the branch, then rebuild and deploy the full Ghost blog app, including user-facing core assets and admin.
  --help  Show this help text.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            FULL_DEPLOY=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

REMOTE_HOST="${REMOTE_HOST:-api.samsar.one}"
REMOTE_USER="${REMOTE_USER:-azureuser}"
REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-/home/azureuser/Blog}"
LIVE_GHOST_DIR="${LIVE_GHOST_DIR:-/var/www/ghost}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/Users/pritamroy/Documents/others/aws/azure/roy_dev_key.pem}"
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
AUTO_COMMIT_MESSAGE="${AUTO_COMMIT_MESSAGE:-chore: sync local blog changes for full deploy}"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "SSH key not found at $SSH_KEY_PATH" >&2
    exit 1
fi

if [[ "$FULL_DEPLOY" == "1" ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Committing local changes for full deploy..."
        git add -A
        git commit -m "$AUTO_COMMIT_MESSAGE"
    else
        echo "No local changes to commit."
    fi
fi

echo "Pushing ${BRANCH} to ${REMOTE_NAME}..."
git push "$REMOTE_NAME" "$BRANCH"
echo "Local commit: $(git rev-parse --short HEAD)"

echo "Deploying on ${REMOTE_USER}@${REMOTE_HOST}..."
ssh -i "$SSH_KEY_PATH" "${REMOTE_USER}@${REMOTE_HOST}" \
    "REMOTE_REPO_DIR='$REMOTE_REPO_DIR' LIVE_GHOST_DIR='$LIVE_GHOST_DIR' BRANCH='$BRANCH' REMOTE_NAME='$REMOTE_NAME' FULL_DEPLOY='$FULL_DEPLOY' bash -s" <<'EOF'
set -euo pipefail

rewrite_workspace_symlinks() {
    local pkg_dir="$1"

    if [[ ! -d "$pkg_dir/node_modules" ]]; then
        return
    fi

    while IFS= read -r link_path; do
        local link_target fixed_target
        link_target="$(readlink "$link_path")"
        fixed_target="${link_target//node_modules\/.pnpm/.pnpm}"
        if [[ "$fixed_target" != "$link_target" ]]; then
            sudo ln -sfn "$fixed_target" "$link_path"
        fi
    done < <(find "$pkg_dir/node_modules" -type l)
}

cd "$REMOTE_REPO_DIR"

echo "Pulling latest code..."
git fetch "$REMOTE_NAME"
git checkout "$BRANCH"
git reset --hard "$REMOTE_NAME/$BRANCH"
git clean -fd
echo "Remote commit: $(git rev-parse --short HEAD)"

echo "Ensuring pnpm workspace file exists..."
cat > pnpm-workspace.yaml <<'WORKSPACE'
packages:
  - 'ghost/core'
  - 'ghost/admin'
  - 'ghost/i18n'
  - 'ghost/parse-email-address'
  - 'apps/admin-x-design-system'
  - 'apps/admin-x-framework'
  - 'apps/admin-x-settings'
  - 'apps/admin'
  - 'apps/activitypub'
  - 'apps/posts'
  - 'apps/shade'
  - 'apps/stats'

catalog:
  '@eslint/js': 8.57.1
  eslint: 8.57.1

catalogs:
  eslint9:
    '@eslint/js': 9.37.0
    eslint: 9.37.0

overrides:
  '@tryghost/errors': ^1.3.7
  '@tryghost/logging': 2.5.5
  jackspeak: 2.3.6
  moment: 2.24.0
  moment-timezone: 0.5.45
  nwsapi: 2.2.23
  broccoli-persistent-filter: ^2.3.1
  juice: 9.1.0
  ember-basic-dropdown: 6.0.2
  ember-in-viewport: 4.1.0
  'eslint-plugin-ghost>@typescript-eslint/eslint-plugin': 8.49.0
  'eslint-plugin-ghost>@typescript-eslint/utils': 8.49.0
  'ember-svg-jar>cheerio': 1.0.0-rc.12
  'juice>cheerio': 0.22.0
  lodash.template: 4.5.0
WORKSPACE

if [[ "${FULL_DEPLOY}" == "1" ]]; then
    echo "Running full blog rebuild..."
    GHOST_UPSTREAM_TAG="v$(node -p "require('./ghost/core/package.json').version.replace(/-rc\\.[0-9]+$/, '')")"
    MISSING_APP_PATHS=()
    for app_path in \
        apps/admin-x-design-system \
        apps/admin-x-framework \
        apps/admin-x-settings \
        apps/admin \
        apps/activitypub \
        apps/posts \
        apps/shade \
        apps/stats
    do
        if [[ ! -f "$app_path/package.json" ]]; then
            MISSING_APP_PATHS+=("$app_path")
        fi
    done

    if (( ${#MISSING_APP_PATHS[@]} > 0 )); then
        echo "Fetching missing Ghost workspace apps from ${GHOST_UPSTREAM_TAG}..."
        TMP_UPSTREAM_DIR="$(mktemp -d)"
        trap 'rm -rf "$TMP_UPSTREAM_DIR"' EXIT
        git clone --depth 1 --branch "$GHOST_UPSTREAM_TAG" --filter=blob:none --sparse https://github.com/TryGhost/Ghost.git "$TMP_UPSTREAM_DIR"
        (
            cd "$TMP_UPSTREAM_DIR"
            git sparse-checkout set "${MISSING_APP_PATHS[@]}"
        )
        mkdir -p apps
        for app_path in "${MISSING_APP_PATHS[@]}"; do
            mkdir -p "$(dirname "$app_path")"
            rsync -a "$TMP_UPSTREAM_DIR/$app_path/" "$app_path/"
        done
        rm -rf "$TMP_UPSTREAM_DIR"
        trap - EXIT
    fi

    node <<'JS'
const fs = require('fs');
const path = require('path');

function replaceOnce(filePath, search, replacement, marker) {
    const fullPath = path.join(process.cwd(), filePath);
    let source = fs.readFileSync(fullPath, 'utf8');

    if (!source.includes(search)) {
        if (marker && source.includes(marker)) {
            return;
        }
        throw new Error(`Could not apply admin compatibility patch to ${filePath}`);
    }

    source = source.replace(search, replacement);
    fs.writeFileSync(fullPath, source);
}

replaceOnce(
    'apps/admin-x-framework/src/api/current-user.ts',
`    const result = useQuery({
        queryKey: currentUserQueryKey,
        queryFn: () => fetchApi<UsersResponseType>(currentUserUrl),
        select: data => data.users[0]
    });`,
`    const result = useQuery({
        queryKey: currentUserQueryKey,
        queryFn: async () => {
            const data = await fetchApi<UsersResponseType>(currentUserUrl);
            const user = data.users[0];

            // Samsar compatibility: older admin API responses can omit roles for users/me.
            if (user && !Array.isArray(user.roles)) {
                try {
                    const usersWithRoles = await fetchApi<UsersResponseType>(apiUrl('/users/', {include: 'roles', limit: '100'}));
                    const userWithRoles = usersWithRoles.users.find(u => u.id === user.id);

                    if (userWithRoles?.roles) {
                        return {
                            ...data,
                            users: [{
                                ...user,
                                roles: userWithRoles.roles
                            }]
                        };
                    }
                } catch {
                    return data;
                }
            }

            return data;
        },
        select: data => data.users[0]
    });`,
    'Samsar compatibility: older admin API responses can omit roles for users/me.'
);

replaceOnce(
    'apps/admin-x-framework/src/api/users.ts',
`// Helpers

export function isOwnerUser(user: User) {
    return user.roles.some(role => role.name === 'Owner');
}

export function isAdminUser(user: User) {
    return user.roles.some(role => role.name === 'Administrator');
}

export function isEditorUser(user: User) {
    const isAnyEditor = user.roles.some(role => role.name === 'Editor')
        || user.roles.some(role => role.name === 'Super Editor');
    return isAnyEditor;
}

export function isSuperEditorUser(user: User) {
    return user.roles.some(role => role.name === 'Super Editor');
}

export function isAuthorUser(user: User) {
    return user.roles.some(role => role.name === 'Author');
}

export function isContributorUser(user: User) {
    return user.roles.some(role => role.name === 'Contributor');
}

export function isAuthorOrContributor(user: User) {
    return isAuthorUser(user) || isContributorUser(user);
}

export function canAccessSettings(user: User) {
    return isOwnerUser(user) || isAdminUser(user) || isEditorUser(user);
}

export function canManageMembers(user: User) {
    // Owner, Admin, or Super Editor can manage members
    return isOwnerUser(user) || isAdminUser(user) || isSuperEditorUser(user);
}

export function canManageTags(user: User) {
    // Owner, Admin or Editor can manage tags
    return isOwnerUser(user) || isAdminUser(user) || isEditorUser(user);
}

export function hasAdminAccess(user: User) {
    return isOwnerUser(user) || isAdminUser(user);
}`,
`// Helpers

type UserRoleLike = Partial<UserRole> | UserRole['name'];
type UserWithOptionalRoles = Omit<User, 'roles'> & {roles?: UserRoleLike[]; role?: UserRoleLike | UserRoleLike[]};

// Samsar compatibility: tolerate current-user payloads that omit roles.
function getUserRoles(user: User): UserRoleLike[] {
    const maybeUser = user as UserWithOptionalRoles;

    if (Array.isArray(maybeUser.roles)) {
        return maybeUser.roles;
    }

    if (Array.isArray(maybeUser.role)) {
        return maybeUser.role;
    }

    return maybeUser.role ? [maybeUser.role] : [];
}

function hasRole(user: User, roleName: UserRole['name']) {
    return getUserRoles(user).some((role) => {
        return typeof role === 'string' ? role === roleName : role?.name === roleName;
    });
}

export function isOwnerUser(user: User) {
    return hasRole(user, 'Owner');
}

export function isAdminUser(user: User) {
    return hasRole(user, 'Administrator');
}

export function isEditorUser(user: User) {
    return hasRole(user, 'Editor') || hasRole(user, 'Super Editor');
}

export function isSuperEditorUser(user: User) {
    return hasRole(user, 'Super Editor');
}

export function isAuthorUser(user: User) {
    return hasRole(user, 'Author');
}

export function isContributorUser(user: User) {
    return hasRole(user, 'Contributor');
}

export function isAuthorOrContributor(user: User) {
    return isAuthorUser(user) || isContributorUser(user);
}

export function canAccessSettings(user: User) {
    return isOwnerUser(user) || isAdminUser(user) || isEditorUser(user);
}

export function canManageMembers(user: User) {
    // Owner, Admin, or Super Editor can manage members
    return isOwnerUser(user) || isAdminUser(user) || isSuperEditorUser(user);
}

export function canManageTags(user: User) {
    // Owner, Admin or Editor can manage tags
    return isOwnerUser(user) || isAdminUser(user) || isEditorUser(user);
}

export function hasAdminAccess(user: User) {
    return isOwnerUser(user) || isAdminUser(user);
}`,
    'Samsar compatibility: tolerate current-user payloads that omit roles.'
);

const samsarAnalyticsPath = path.join(process.cwd(), 'apps/stats/src/views/SamsarAnalytics/samsar-analytics.tsx');
fs.mkdirSync(path.dirname(samsarAnalyticsPath), {recursive: true});
fs.writeFileSync(samsarAnalyticsPath, `import DateRangeSelect from '../Stats/components/date-range-select';
import React, {useMemo} from 'react';
import StatsHeader from '../Stats/layout/stats-header';
import StatsLayout from '../Stats/layout/stats-layout';
import StatsView from '../Stats/layout/stats-view';
import {ALL_AUDIENCES} from '@src/utils/constants';
import {Card, CardContent, CardHeader, CardTitle, NavbarActions} from '@tryghost/shade/components';
import {LucideIcon, formatNumber} from '@tryghost/shade/utils';
import {formatQueryDate, getRangeDates} from '@tryghost/shade/app';
import {getAudienceQueryParam} from '@src/utils/audience';
import {useGlobalData} from '@src/providers/global-data-provider';
import {useTinybirdQuery} from '@tryghost/admin-x-framework';
import {useTopPostsViews} from '@tryghost/admin-x-framework/api/stats';

type KpiRow = {
    pageviews?: number;
    visits?: number;
};

type SourceRow = {
    source?: string | number;
    visits?: number;
    pageviews?: number;
};

interface MetricCardProps {
    detail: string;
    icon: React.ReactNode;
    isLoading?: boolean;
    title: string;
    value: string;
}

const toNumber = (value: unknown) => {
    const numberValue = Number(value);
    return Number.isFinite(numberValue) ? numberValue : 0;
};

const formatSource = (source: SourceRow['source']) => {
    if (source === undefined || source === null || source === '') {
        return 'Direct / unknown';
    }

    return String(source);
};

const EmptyBlock: React.FC<{children: React.ReactNode}> = ({children}) => (
    <div className='flex min-h-[180px] items-center justify-center rounded-md border border-dashed border-border px-6 text-center text-sm text-muted-foreground'>
        {children}
    </div>
);

const MetricCard: React.FC<MetricCardProps> = ({
    detail,
    icon,
    isLoading = false,
    title,
    value
}) => (
    <Card>
        <CardHeader>
            <CardTitle className='flex items-center justify-between text-sm font-medium text-muted-foreground'>
                <span>{title}</span>
                {icon}
            </CardTitle>
        </CardHeader>
        <CardContent>
            {isLoading ? (
                <div className='h-9 w-28 animate-pulse rounded bg-muted' />
            ) : (
                <div className='text-3xl font-semibold tracking-normal'>{value}</div>
            )}
            <div className='mt-2 text-sm text-muted-foreground'>{detail}</div>
        </CardContent>
    </Card>
);

const SamsarAnalytics: React.FC = () => {
    const {statsConfig, isLoading: isConfigLoading, range} = useGlobalData();
    const {startDate, endDate, timezone} = getRangeDates(range);
    const dateFrom = formatQueryDate(startDate);
    const dateTo = formatQueryDate(endDate);

    const tinybirdParams = useMemo(() => ({
        site_uuid: statsConfig?.id || '',
        date_from: dateFrom,
        date_to: dateTo,
        timezone,
        member_status: getAudienceQueryParam(ALL_AUDIENCES)
    }), [statsConfig?.id, dateFrom, dateTo, timezone]);

    const {data: topPostsData, isLoading: isTopPostsLoading} = useTopPostsViews({
        searchParams: {
            date_from: dateFrom,
            date_to: dateTo,
            limit: '20',
            timezone
        }
    });

    const {data: kpiData, loading: isKpiLoading} = useTinybirdQuery({
        endpoint: 'api_kpis',
        statsConfig,
        params: tinybirdParams,
        enabled: Boolean(statsConfig)
    });

    const {data: sourcesData, loading: isSourcesLoading} = useTinybirdQuery({
        endpoint: 'api_top_sources',
        statsConfig,
        params: tinybirdParams,
        enabled: Boolean(statsConfig)
    });

    const topPosts = topPostsData?.stats || [];
    const kpiRows = (kpiData as KpiRow[] | undefined) || [];
    const sourceRows = ((sourcesData as SourceRow[] | undefined) || []).slice(0, 5);
    const topPostViews = topPosts.reduce((sum, post) => sum + toNumber(post.views), 0);
    const trackedViews = kpiRows.reduce((sum, row) => sum + toNumber(row.pageviews), 0);
    const totalViews = statsConfig ? trackedViews : topPostViews;
    const topSource = sourceRows[0];
    const topSourceVisits = topSource ? toNumber(topSource.visits ?? topSource.pageviews) : 0;

    return (
        <StatsLayout>
            <StatsHeader>
                <NavbarActions>
                    <DateRangeSelect excludeRanges={['today']} />
                </NavbarActions>
            </StatsHeader>
            <StatsView isLoading={isConfigLoading} loadingComponent={<></>}>
                <div className='grid grid-cols-1 gap-6 lg:grid-cols-3'>
                    <MetricCard
                        detail={statsConfig ? 'Pageviews in the selected range' : 'Top post views in the selected range'}
                        icon={<LucideIcon.ChartColumnIncreasing className='text-muted-foreground' size={18} strokeWidth={1.5} />}
                        isLoading={statsConfig ? isKpiLoading : isTopPostsLoading}
                        title='Views'
                        value={formatNumber(totalViews)}
                    />
                    <MetricCard
                        detail='Top posts returned for this range'
                        icon={<LucideIcon.FileText className='text-muted-foreground' size={18} strokeWidth={1.5} />}
                        isLoading={isTopPostsLoading}
                        title='Posts'
                        value={formatNumber(topPosts.length)}
                    />
                    <MetricCard
                        detail={topSource ? formatNumber(topSourceVisits) + ' visits' : 'Source data is available when web analytics is configured'}
                        icon={<LucideIcon.Globe className='text-muted-foreground' size={18} strokeWidth={1.5} />}
                        isLoading={Boolean(statsConfig) && isSourcesLoading}
                        title='Top source'
                        value={topSource ? formatSource(topSource.source) : 'Unavailable'}
                    />
                </div>

                <div className='grid grid-cols-1 gap-6 lg:grid-cols-2'>
                    <Card>
                        <CardHeader>
                            <CardTitle>Top posts</CardTitle>
                        </CardHeader>
                        <CardContent>
                            {isTopPostsLoading ? (
                                <div className='flex flex-col gap-3'>
                                    {[0, 1, 2, 3, 4].map(item => (
                                        <div key={item} className='h-11 animate-pulse rounded bg-muted' />
                                    ))}
                                </div>
                            ) : topPosts.length > 0 ? (
                                <div className='flex flex-col'>
                                    {topPosts.map(post => (
                                        <div key={post.post_id} className='flex items-start justify-between gap-4 border-t border-border/50 py-3 first:border-t-0'>
                                            <div className='min-w-0'>
                                                <div className='truncate font-medium'>{post.title || 'Untitled post'}</div>
                                                <div className='text-sm text-muted-foreground'>{post.status}</div>
                                            </div>
                                            <div className='shrink-0 font-mono text-sm'>{formatNumber(toNumber(post.views))}</div>
                                        </div>
                                    ))}
                                </div>
                            ) : (
                                <EmptyBlock>No post view data is available for this range.</EmptyBlock>
                            )}
                        </CardContent>
                    </Card>

                    <Card>
                        <CardHeader>
                            <CardTitle>Top sources</CardTitle>
                        </CardHeader>
                        <CardContent>
                            {!statsConfig ? (
                                <EmptyBlock>Source data is not available because web analytics is not configured for this install.</EmptyBlock>
                            ) : isSourcesLoading ? (
                                <div className='flex flex-col gap-3'>
                                    {[0, 1, 2, 3, 4].map(item => (
                                        <div key={item} className='h-11 animate-pulse rounded bg-muted' />
                                    ))}
                                </div>
                            ) : sourceRows.length > 0 ? (
                                <div className='flex flex-col'>
                                    {sourceRows.map((source, index) => (
                                        <div key={String(source.source || index)} className='flex items-center justify-between gap-4 border-t border-border/50 py-3 first:border-t-0'>
                                            <div className='min-w-0 truncate font-medium'>{formatSource(source.source)}</div>
                                            <div className='shrink-0 font-mono text-sm'>{formatNumber(toNumber(source.visits ?? source.pageviews))}</div>
                                        </div>
                                    ))}
                                </div>
                            ) : (
                                <EmptyBlock>No source data is available for this range.</EmptyBlock>
                            )}
                        </CardContent>
                    </Card>
                </div>
            </StatsView>
        </StatsLayout>
    );
};

export default SamsarAnalytics;
`);

replaceOnce(
    'apps/stats/src/routes.tsx',
`                lazy: lazyComponent(() => import('./views/Stats/Overview'))`,
`                lazy: lazyComponent(() => import('./views/SamsarAnalytics/samsar-analytics'))`,
    './views/SamsarAnalytics/samsar-analytics'
);

replaceOnce(
    'apps/admin/src/layout/app-sidebar/nav-main.tsx',
`    // Only show NavMain for admin users
    if (!currentUser || !hasAdminAccess(currentUser)) {
        return null;
    }`,
`    const rolesAreLoaded = Array.isArray(currentUser?.roles) && currentUser.roles.length > 0;

    // Samsar compatibility: keep the full admin nav visible while legacy current-user roles hydrate.
    if (!currentUser || (rolesAreLoaded && !hasAdminAccess(currentUser))) {
        return null;
    }`,
    'Samsar compatibility: keep the full admin nav visible while legacy current-user roles hydrate.'
);

replaceOnce(
    'apps/admin/src/layout/app-sidebar/nav-settings.tsx',
`    const { data: currentUser } = useCurrentUser();
    const showSettings = currentUser && canAccessSettings(currentUser);`,
`    const { data: currentUser } = useCurrentUser();
    const rolesAreLoaded = Array.isArray(currentUser?.roles) && currentUser.roles.length > 0;
    const showSettings = currentUser && (!rolesAreLoaded || canAccessSettings(currentUser));`,
    'const showSettings = currentUser && (!rolesAreLoaded || canAccessSettings(currentUser));'
);

replaceOnce(
    'apps/admin/src/layout/app-sidebar/nav-content.tsx',
`    const showTags = currentUser && canManageTags(currentUser);
    const showMembers = currentUser && canManageMembers(currentUser);`,
`    const rolesAreLoaded = Array.isArray(currentUser?.roles) && currentUser.roles.length > 0;
    const showTags = currentUser && (!rolesAreLoaded || canManageTags(currentUser));
    const showMembers = currentUser && (!rolesAreLoaded || canManageMembers(currentUser));`,
    'const showTags = currentUser && (!rolesAreLoaded || canManageTags(currentUser));'
);
JS

    node <<'JS'
const fs = require('fs');
const path = require('path');

const packageJsonPath = path.join(process.cwd(), 'package.json');
const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));

pkg.devDependencies = {
    ...(pkg.devDependencies || {}),
    esbuild: '0.25.12',
    lodash: '4.17.23',
    semver: '7.7.4'
};

pkg.pnpm = {
    ...(pkg.pnpm || {}),
    onlyBuiltDependencies: [
        '@swc/core',
        'core-js',
        'cpu-features',
        'dtrace-provider',
        'esbuild',
        'fsevents',
        'msw',
        'nx',
        'protobufjs',
        're2',
        'sharp',
        'sqlite3',
        'ssh2'
    ]
};

fs.writeFileSync(packageJsonPath, `${JSON.stringify(pkg, null, 2)}\n`);
JS

    corepack enable
    CI=true pnpm install --no-frozen-lockfile --config.confirmModulesPurge=false
    (cd ghost/parse-email-address && pnpm build)
    (cd ghost/core && pnpm build:assets)
    pnpm --filter @tryghost/shade build
    pnpm --filter @tryghost/admin-x-design-system build
    pnpm --filter @tryghost/admin-x-framework build
    pnpm --filter @tryghost/admin-x-settings build
    pnpm --filter @tryghost/activitypub build
    pnpm --filter @tryghost/posts build
    pnpm --filter @tryghost/stats build
    (cd ghost/admin && pnpm build)
    pnpm --filter @tryghost/admin build

    echo "Syncing full Ghost runtime into active Ghost version directory..."
    LIVE_GHOST_VERSION_DIR="$(readlink -f "$LIVE_GHOST_DIR/current" 2>/dev/null || true)"
    if [[ -z "$LIVE_GHOST_VERSION_DIR" || ! -d "$LIVE_GHOST_VERSION_DIR" ]]; then
        LIVE_GHOST_VERSION_DIR="$(find "$LIVE_GHOST_DIR/versions" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
    fi
    if [[ -z "$LIVE_GHOST_VERSION_DIR" || ! -d "$LIVE_GHOST_VERSION_DIR" ]]; then
        echo "Could not determine active Ghost version directory under $LIVE_GHOST_DIR/versions" >&2
        exit 1
    fi

    sudo rsync -a --delete \
        --exclude 'content/' \
        --exclude 'node_modules/' \
        --exclude '.git/' \
        --exclude '.cache/' \
        --exclude 'config*.json' \
        "$REMOTE_REPO_DIR/ghost/core/" "$LIVE_GHOST_VERSION_DIR/"

    sudo rm -rf "$LIVE_GHOST_DIR/node_modules"
    sudo rsync -a "$REMOTE_REPO_DIR/node_modules/" "$LIVE_GHOST_DIR/node_modules/"
    sudo mkdir -p "$LIVE_GHOST_DIR/node_modules/@tryghost"
    sudo rsync -a --delete "$REMOTE_REPO_DIR/ghost/i18n/" "$LIVE_GHOST_DIR/node_modules/@tryghost/i18n/"
    sudo rsync -a --delete "$REMOTE_REPO_DIR/ghost/parse-email-address/" "$LIVE_GHOST_DIR/node_modules/@tryghost/parse-email-address/"
    rewrite_workspace_symlinks "$LIVE_GHOST_DIR/node_modules/@tryghost/i18n"
    rewrite_workspace_symlinks "$LIVE_GHOST_DIR/node_modules/@tryghost/parse-email-address"
    sudo rm -rf "$LIVE_GHOST_VERSION_DIR/node_modules"
    sudo rsync -a "$REMOTE_REPO_DIR/ghost/core/node_modules/" "$LIVE_GHOST_VERSION_DIR/node_modules/"
    sudo ln -sfn "../../../../node_modules/@tryghost/i18n" "$LIVE_GHOST_VERSION_DIR/node_modules/@tryghost/i18n"
    sudo ln -sfn "../../../../node_modules/@tryghost/parse-email-address" "$LIVE_GHOST_VERSION_DIR/node_modules/@tryghost/parse-email-address"

    sudo ln -sfn "$LIVE_GHOST_VERSION_DIR" "$LIVE_GHOST_DIR/current"
    sudo LIVE_GHOST_DIR="$LIVE_GHOST_DIR" LIVE_GHOST_VERSION_DIR="$LIVE_GHOST_VERSION_DIR" node <<'JS'
const fs = require('fs');
const path = require('path');

const installDir = process.env.LIVE_GHOST_DIR;
const versionDir = process.env.LIVE_GHOST_VERSION_DIR;
const version = path.basename(versionDir);
const cliPath = path.join(installDir, '.ghost-cli');

const cliConfig = {
    'active-version': version,
    'cli-version': '1.29.1',
    'node-version': process.versions.node,
    channel: 'stable',
    name: 'ghost-localhost',
    running: 'production'
};

fs.writeFileSync(cliPath, `${JSON.stringify(cliConfig, null, 2)}\n`);
JS
fi

echo "Syncing samsar theme into live Ghost content directory..."
sudo mkdir -p "$LIVE_GHOST_DIR/content/themes/samsar"
sudo rsync -a --delete "$REMOTE_REPO_DIR/ghost/core/content/themes/samsar/" "$LIVE_GHOST_DIR/content/themes/samsar/"
sudo chown -R ghost:ghost "$LIVE_GHOST_DIR/content/themes/samsar"

echo "Ensuring live Ghost upload directories are writable..."
sudo mkdir -p \
    "$LIVE_GHOST_DIR/content/images" \
    "$LIVE_GHOST_DIR/content/media" \
    "$LIVE_GHOST_DIR/content/files"
sudo chown -R ghost:ghost \
    "$LIVE_GHOST_DIR/content/images" \
    "$LIVE_GHOST_DIR/content/media" \
    "$LIVE_GHOST_DIR/content/files"
sudo find \
    "$LIVE_GHOST_DIR/content/images" \
    "$LIVE_GHOST_DIR/content/media" \
    "$LIVE_GHOST_DIR/content/files" \
    -type d -exec chmod 775 {} +
sudo find \
    "$LIVE_GHOST_DIR/content/images" \
    "$LIVE_GHOST_DIR/content/media" \
    "$LIVE_GHOST_DIR/content/files" \
    -type f -exec chmod 664 {} +

echo "Listing deployed theme files..."
sudo find "$LIVE_GHOST_DIR/content/themes/samsar" -maxdepth 2 -type f | sort | sed -n '1,80p'

echo "Setting live Ghost URL to /blog..."
sudo LIVE_GHOST_DIR="$LIVE_GHOST_DIR" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["LIVE_GHOST_DIR"]) / "config.production.json"
with path.open() as f:
    data = json.load(f)

data["url"] = "https://www.samsar.one/blog/"
data.setdefault("security", {})["staffDeviceVerification"] = False

with path.open("w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "Activating samsar theme in Ghost database..."
mysql -u ghost_user -pstrong_password -D ghost_prod -e "update settings set value='samsar' where \`key\`='active_theme';"

echo "Clearing stale migration lock if present..."
mysql -u ghost_user -pstrong_password -D ghost_prod -e "update migrations_lock set locked=0, acquired_at=NULL where lock_key='km01';" || true

echo "Restarting live Ghost service..."
sudo systemctl restart ghost_localhost.service
sleep 8
sudo systemctl --no-pager --full status ghost_localhost.service | sed -n '1,40p'

echo "Smoke testing public blog URL..."
curl -I https://www.samsar.one/blog/
EOF

echo "Deploy complete."
