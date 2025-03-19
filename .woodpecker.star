config = {
    'name': 'cs3api-validator',
    'rocketchat': {
        'channel': 'builds',
        'from_secret': 'private_rocketchat'
    },
    'branches': [
        'main'
    ],
}

def main(ctx):
    before = beforePipelines(ctx)
    if not before:
        print('Errors detected. Review messages above.')
        return []
    stages = stagePipelines(ctx)
    if not stages:
        print('Errors detected. Review messages above.')
        return []
    dependsOn(before, stages)
    after = afterPipelines(ctx)
    dependsOn(stages, after)
    return before + stages + after

def beforePipelines(ctx):
    return linting(ctx)

def stagePipelines(ctx):
    # testPipelines = tests(ctx)
    dockerReleasePipelines = dockerRelease(ctx, "amd64")
    # dependsOn(testPipelines, dockerReleasePipelines)
    dockerAfterRelease = releaseDockerReadme(ctx)
    dependsOn(dockerReleasePipelines, dockerAfterRelease)
    #return testPipelines + dockerReleasePipelines + dockerAfterRelease
    return dockerReleasePipelines + dockerAfterRelease

def afterPipelines(ctx):
    return [
        notify()
    ]

def dependsOn(earlierStages, nextStages):
    for earlierStage in earlierStages:
        for nextStage in nextStages:
            nextStage['depends_on'].append(earlierStage['name'])

def notify():
    result = {
        'name': 'chat-notifications',
        'skip_clone': True,
        'steps': [
            {
                'name': 'notify-rocketchat',
                'image': 'plugins/slack:1',
                'settings': {
                    'webhook': {
                        'from_secret': config['rocketchat']['from_secret']
                    },
                    'channel': config['rocketchat']['channel']
                }
            }
        ],
        'depends_on': [],
        'when': [
            {
                'event': 'tag',
                'status': ['success', 'failure'],
            },
        ],
    }

    for branch in config['branches']:
        result['when'] += { "event": "push", "branch": "%s" % branch }

    return result

def linting(ctx):
    pipelines = []

    result = {
        'name': 'lint',
        'steps': [
            {
                "name": "validate-go",
                "image": "golangci/golangci-lint:latest",
                "commands": [
                    "golangci-lint run -v",
                ]
            },
        ],
        'depends_on': [],
        'when': [
            {
                'event': 'pull_request',
            },
            {
                'event': 'tag',
            },
        ],
    }

    for branch in config['branches']:
        result['when'] += { "event": "push", "branch": "%s" % branch }

    pipelines.append(result)

    return pipelines

def tests(ctx):
    pipelines = []
    result = {
        'name': 'test-acceptance-cs3api',
        'steps': [
            {
                "name": "wait-for-opencloud",
                "image": "owncloudci/wait-for:latest",
                "commands": [
                    "wait-for -it opencloud:9200 -t 300",
                ],
            },
            {
                "name": "test",
                "image": "golang:1.24",
                "commands": [
                    "go test --endpoint=opencloud:9142 -v",
                ],
            },
        ],
        'services': openCloudService(),
        'depends_on': [],
        'when': [
            {
                'event': 'pull_request',
            },
            {
                'event': 'tag',
            },
        ],
    }

    for branch in config['branches']:
        result['when'] += { "event": "push", "branch": "%s" % branch }

    pipelines.append(result)

    return pipelines

def openCloudService():
    return [{
        "name": "opencloud",
        "image": "quay.io/opencloudeu/opencloud-rolling:latest",
        "pull": "always",
        "detach": True,
        "environment": {
            "OC_URL": "https://opencloud:9200",
            "OC_LOG_LEVEL": "error",
            "GATEWAY_GRPC_ADDR": "0.0.0.0:9142",
            "IDM_ADMIN_PASSWORD": "admin",
            "IDM_CREATE_DEMO_USERS": True,
        },
        "commands": [
            "opencloud init --insecure true",
            "opencloud server",
        ],
    }]

def dockerRelease(ctx, arch):
    pipelines = []
    repo = "opencloudeu/cs3api-validator"
    build_args = [
        "REVISION=%s" % (ctx.build.commit),
        "VERSION=%s" % (ctx.build.ref.replace("refs/tags/", "") if ctx.build.event == "tag" else "latest"),
    ]

    result = {
        "name": "container-build",
        "steps": [
            {
                "name": "dryrun",
                "image": "woodpeckerci/plugin-docker-buildx:latest",
                "settings": {
                    "dry_run": True,
                    "platforms": "linux/amd64",  # do dry run only on the native platform
                    "repo": "%s,quay.io/%s" % (repo, repo),
                    "auto_tag": True,
                    "default_tag": "daily",
                    "dockerfile": "docker/Dockerfile.multiarch",
                    "build_args": build_args,
                    "pull_image": False,
                    "http_proxy": {
                        "from_secret": "ci_http_proxy",
                    },
                    "https_proxy": {
                        "from_secret": "ci_http_proxy",
                    },
                },
                "when": [
                    {
                        "event": "pull_request",
                    },
                ],
            },
            {
                "name": "docker",
                "image": "woodpeckerci/plugin-docker-buildx:latest",
                "settings": {
                    "repo": "%s,quay.io/%s" % (repo, repo),
                    "platforms": "linux/amd64,linux/arm64",  # we can add remote builders
                    "auto_tag": True,
                    "default_tag": "daily",
                    "dockerfile": "docker/Dockerfile.multiarch",
                    "build_args": build_args,
                    "pull_image": False,
                    "http_proxy": {
                        "from_secret": "ci_http_proxy",
                    },
                    "https_proxy": {
                        "from_secret": "ci_http_proxy",
                    },
                    "logins": [
                        {
                            "registry": "https://index.docker.io/v1/",
                            "username": {
                                "from_secret": "docker_username",
                            },
                            "password": {
                                "from_secret": "docker_password",
                            },
                        },
                        {
                            "registry": "https://quay.io",
                            "username": {
                                "from_secret": "quay_username",
                            },
                            "password": {
                                "from_secret": "quay_password",
                            },
                        },
                    ],
                },
                "when": [
                    {
                        "event": "tag",
                    },
                ],
            },
        ],
        "depends_on": [],
        "when": [
            {
                "event": "pull_request",
            },
            {
                "event": "tag",
            },
        ],
    }

    pipelines.append(result)
    return pipelines

def releaseDockerReadme(ctx):
    pipelines = []
    result = {
        "name": "readme",
        "steps": [
            {
                "name": "push-docker",
                "image": "chko/docker-pushrm:1",
                "environment": {
                    "DOCKER_USER": {
                        "from_secret": "docker_username",
                    },
                    "DOCKER_PASS": {
                        "from_secret": "docker_password",
                    },
                    "PUSHRM_TARGET": "opencloudeu/%s" % ctx.repo.name,
                    "PUSHRM_SHORT": "Docker images for %s" % ctx.repo.name,
                    "PUSHRM_FILE": "README.md",
                },
            },
            {
                "name": "push-quay",
                "image": "chko/docker-pushrm:1",
                "environment": {
                    "APIKEY__QUAY_IO": {
                        "from_secret": "quay_apikey"
                    },
                    "PUSHRM_TARGET": "quay.io/%s" % ctx.repo.name,
                    "PUSHRM_FILE": "README.md",
                    "PUSHRM_PROVIDER": "quay",
                },
            }
        ],
        "depends_on": [],
        "when": [
            {
                "event": "tag",
            },
        ],
    }
    for branch in config['branches']:
        result['when'] += { "event": "push", "branch": "%s" % branch }

    pipelines.append(result)
    return pipelines

def getPipelineNames(pipelines = []):
    """getPipelineNames returns names of pipelines as a string array

    Args:
      pipelines: array of drone pipelines

    Returns:
      names of the given pipelines as string array
    """
    names = []
    for pipeline in pipelines:
        names.append(pipeline["name"])
    return names
