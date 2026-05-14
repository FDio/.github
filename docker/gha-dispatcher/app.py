import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from re import match
from subprocess import CalledProcessError, CompletedProcess, PIPE, Popen, STDOUT
from tempfile import NamedTemporaryFile
from time import sleep
from typing import Dict, List

import requests


logging.basicConfig(
    level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s'
)


@dataclass
class Config:
    """Configuration loaded from environment variables with defaults."""
    dh_repo: str = "fdiotools"
    gh_api_url: str = "https://api.github.com/repos"
    gh_account: str = os.getenv("GITHUB_ACCOUNT", "repos")
    gh_pat: str = os.getenv("GITHUB_PAT", "")
    gh_repo: str = os.getenv("GITHUB_REPO", "pmikus/gha-nomad-docker")
    gh_namespace: str = os.getenv("GITHUB_LABEL_NAMESPACE", "fdio")
    nomad_addr: str = os.getenv("NOMAD_ADDR", "http://10.30.51.24:4646")
    nomad_namespace: str = os.getenv("NOMAD_NAMESPACE", "prod")

    def validate(self) -> None:
        """Raise EnvironmentError if any config value is empty."""
        missing = [k for k, v in vars(self).items() if not v]
        if missing:
            raise EnvironmentError(f"Missing env vars: {', '.join(missing)}")


class ResourceSize(str, Enum):
    """Runner resource profiles."""
    CSIT = "csit"
    VPP = "vpp"
    HST = "hst"

    @classmethod
    def _missing_(cls, value):
        return cls.VPP

    @property
    def cpu(cls) -> str:
        """CPU resource allocation."""
        if cls is cls.VPP:
            return "24000"
        elif cls is cls.CSIT:
            return "16000"
        elif cls is cls.HST:
            return "262144"
        else:
            return "12000"

    @property
    def memory(cls) -> str:
        """Memory resource allocation."""
        if cls is cls.VPP:
            return "24000"
        elif cls is cls.CSIT:
            return "16384"
        elif cls is cls.HST:
            return "128000"
        else:
            return "12000"


class CpuArchitecture(str, Enum):
    """Supported CPU architectures."""
    X86_64 = "x86_64"
    AARCH64 = "aarch64"

    @classmethod
    def _missing_(cls, value):
        return cls.X86_64

    @property
    def constraint(cls) -> str:
        return {"x86_64": "amd64", "aarch64": "arm64"}[cls.value]


class ImageOs(str, Enum):
    """Runner image operating systems."""
    UBUNTU_2604 = "ubuntu2604"
    UBUNTU_2404 = "ubuntu2404"
    UBUNTU_2204 = "ubuntu2204"
    DEBIAN_13 = "debian13"
    DEBIAN_12 = "debian12"

    @classmethod
    def _missing_(cls, value):
        return cls.UBUNTU_2404

    def __str__(self) -> str:
        return str.__str__(self)


class NodeClass(str, Enum):
    """Runner node classes."""
    BUILDER = "builder"
    HST = "hst"

    @classmethod
    def _missing_(cls, value):
        return cls.BUILDER

    def __str__(self) -> str:
        return str.__str__(self)


headers = {
    "Authorization": f"token {Config().gh_pat}",
    "Accept": "application/vnd.github+json",
}


def parse_labels(labels: List[str]) -> Dict[str, str]:
    """
    Parse GitHub runner labels into dictionary.

    Args:
        labels (list): The response object from the successful request.
    """
    parsed = {}
    for label in labels:
        if label.startswith(Config().gh_namespace + ":"):
            _, kv = label.split(":", 1)
            if "=" in kv:
                key, value = kv.split("=", 1)
                parsed[key] = value
    return parsed


def nomad_allocations() -> dict:
    """
    Get All Nomad allocations that are in running state.
    """
    try:
        url = f"{Config().nomad_addr}/v1/allocations"
        params = {
            "namespace": Config().nomad_namespace,
            "task_states": "false",
            "resources": "false"
        }
        response = requests.get(url=url, params=params, timeout=10)
        if response.ok:
            response.raise_for_status()
            return [
                alloc for alloc in response.json() if alloc["JobType"] == \
                "batch" and alloc["ClientStatus"] == "running"
            ]
    except requests.exceptions.RequestException as e:
        on_failure(f"An error occurred during the request: {e}")


def nomad_jobs() -> dict:
    """
    Get All Nomad jobs of batch type.
    """
    try:
        url = f"{Config().nomad_addr}/v1/jobs"
        params = {
            "namespace": Config().nomad_namespace,
            "prefix": "gha-"
        }
        response = requests.get(url=url, params=params, timeout=10)
        if response.ok:
            response.raise_for_status()
            return [job for job in response.json() if job["Type"] == "batch"]
    except requests.exceptions.RequestException as e:
        on_failure(f"An error occurred during the request: {e}")


def nomad_job_allocations(job_id: str) -> str:
    """
    Get Nomad allocations for specified job ID.

    Args:
        job_id (str): Nomad Job ID.
    """
    try:
        url = f"{Config().nomad_addr}/v1/job/{job_id}/allocations"
        params = {
            "namespace": Config().nomad_namespace
        }
        response = requests.get(url=url, params=params, timeout=10)
        if response.ok:
            response.raise_for_status()
            return response.json()[-1]["ID"]
    except requests.exceptions.RequestException as e:
        on_failure(f"An error occurred during the request: {e}")


def nomad_purge_job(job_id: str) -> None:
    """
    Stop Nomad job and purge.

    Args:
        job_id (str): Nomad Job ID.
    """
    try:
        url = f"{Config().nomad_addr}/v1/job/{job_id}"
        params = {
            "namespace": Config().nomad_namespace,
            "purge": "true"
        }
        response = requests.delete(url=url, params=params, timeout=10)
        if response.ok:
            response.raise_for_status()
    except requests.exceptions.RequestException as e:
        on_failure(f"An error occurred during the request: {e}")

def nomad_system_gc() -> None:
    """
    Initializes a garbage collection of jobs, evaluations, allocations, and
    nodes.
    """
    try:
        url = f"{Config().nomad_addr}/v1/system/gc"
        response = requests.put(url=url, timeout=10)
        if response.ok:
            response.raise_for_status()
    except requests.exceptions.RequestException as e:
        on_failure(f"An error occurred during the request: {e}")


def nomad_environment(
        job_id: str,
        labels: List[str],
        parsed_labels: Dict[str, str]
    ) -> Dict[str, str]:
    """
    Create NOMAD_VAR environment variables.

    Args:
        job_id (int): GitHub Action Job ID.
        labels (list): Unparsed list of self-hosted labels.
        parsed_labels (Dict): Parsed Dict of self-hosted labels.
    """
    node_arch = CpuArchitecture(parsed_labels.get("arch", "x86_64"))
    constraint_arch = CpuArchitecture(node_arch).constraint
    constraint_class = NodeClass(parsed_labels.get("class", "builder")).value
    resource_size = ResourceSize(parsed_labels.get("size", "vpp"))
    cpu = ResourceSize(resource_size).cpu
    memory = ResourceSize(resource_size).memory
    image_os = ImageOs(parsed_labels.get("os", "ubuntu2404")).value
    image = f"{Config().dh_repo}/gha-{image_os}:{Config().nomad_namespace}-{node_arch.value}"
    if "dev" in Config().nomad_namespace:
        image = f"{Config().dh_repo}/gha-{image_os}:sandbox-{node_arch.value}"
    github_api_url = f"https://api.github.com/repos/{Config().gh_repo}"
    github_repo_url = f"https://github.com/{Config().gh_repo}"

    return {
        "NOMAD_VAR_name": f"gha-{job_id}",
        "NOMAD_VAR_namespace": Config().nomad_namespace,
        "NOMAD_VAR_constraint_arch": constraint_arch,
        "NOMAD_VAR_constraint_class": constraint_class,
        "NOMAD_VAR_image": image,
        "NOMAD_VAR_cpu": cpu,
        "NOMAD_VAR_memory": memory,
        "NOMAD_VAR_os": image_os,
        "NOMAD_VAR_env_runner_labels": ",".join(labels),
        "NOMAD_VAR_github_api_url": github_api_url,
        "NOMAD_VAR_github_repo_url": github_repo_url
    }


def trigger_runner_job(run: Dict) -> None:
    """
    Trigger Nomad Job.

    Args:
        run (Dict): Github Action workflow run.
    """
    run_id = run["id"]
    jobs_url = f"{Config().gh_api_url}/{Config().gh_repo}/actions/runs/{run_id}/jobs"
    jobs_response = requests.get(url=jobs_url, headers=headers)
    jobs_response.raise_for_status()
    jobs = jobs_response.json().get("jobs", [])

    for job in jobs:
        if "queued" not in job["status"]:
            continue
        job_id = job["id"]
        labels = job["labels"] if "labels" in job else []
        parsed_labels = parse_labels(labels)

        logging.info(f"Found: {run_id} | {set(labels)}")

        if "nomad" not in labels:
            continue
        if parsed_labels.get("namespace", "prod") != Config().nomad_namespace:
            continue

        with (
            open("job.nomad.hcl", "r") as src,
            NamedTemporaryFile(mode="w", suffix=".hcl", delete=True) as tmp,
        ):
            logging.info(f"Starting: {run_id} | {set(labels)}")
            tmp_file_path = Path(tmp.name)
            cmd = ["nomad", "job", "run", tmp_file_path]
            env = os.environ | nomad_environment(job_id, labels, parsed_labels)
            tmp.write(src.read().replace('"gha-runner"', f"{env['NOMAD_VAR_name']}"))
            tmp.flush()
            try:
                with Popen(cmd, env=env, stdout=PIPE, stderr=STDOUT, text=True) as proc:
                    errs = []
                    for line in proc.stdout:
                        logging.info(line.strip())
                        errs.append(line)
                    stdout, _ = proc.communicate()
                    if proc.returncode != 0:
                        raise CalledProcessError(
                            proc.returncode, cmd, stdout, "\n".join(errs)
                        )
                CompletedProcess(cmd, proc.returncode, stdout, "\n".join(errs))
            except CalledProcessError as e:
                logging.error(f"Nomad job failed: {e.stderr}")
                pass


def trigger_garbage_collector() -> None:
    """
    Execute Nomad job purge for orphaned GHA runners.
    """
    for alloc in nomad_allocations():
        fmt = "%Y-%m-%d %H:%M:%SZ"
        cmd = [
            "nomad", "alloc", "logs", "-namespace",
            Config().nomad_namespace, "-stdout", alloc["ID"]
        ]
        env = os.environ
        try:
            with Popen(cmd, env=env, stdout=PIPE, stderr=STDOUT, text=True) as proc:
                errs = ""
                for line in proc.stdout:
                    errs = line.strip()
                _, _ = proc.communicate()
                if proc.returncode == 0 and "Listening for Jobs" in errs:
                    now = datetime.now(timezone.utc)
                    dmatch = match(
                        r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z):", errs).group(1)
                    log = datetime.strptime(dmatch, fmt).replace(tzinfo=timezone.utc)
                    if (now - log).total_seconds() > 3600.0:
                        logging.info("Purging", alloc["JobID"])
                        nomad_purge_job(alloc["JobID"])
        except CalledProcessError as e:
            logging.info(f"Nomad job failed: {e.stderr}")
            pass
    nomad_system_gc()


def on_success(response: requests.Response) -> None:
    """
    This function is executed when the URL check is successful.

    Args:
        response (requests.Responses): The response object from the request.
    """
    logging.info(f"Status code {response.status_code} for {response.url}")
    runs = response.json().get("workflow_runs", [])
    if runs:
        for run in runs:
            trigger_runner_job(run)
    trigger_garbage_collector()


def on_failure(response: requests.Response) -> None:
    """
    This function is executed when the URL check fails or an error occurs.

    Args:
        response (requests.Responses): The response object from the request.
    """
    logging.warning(f"Status code {response.status_code} for {response.url}")


def check_api_status(interval: int = 30) -> None:
    """
    Periodically checks the status of a given URL and takes action based on
    the result.

    Args:
        interval (int): The time in seconds to wait between checks.
    """
    logging.info(f"Starting API status checker...")
    while True:
        try:
            url = f"{Config().gh_api_url}/{Config().gh_repo}/actions/runs"
            params = {"status": "queued"}
            response = requests.get(
                url=url, headers=headers, params=params, timeout=10
            )
            if response.ok:
                on_success(response)
            else:
                on_failure(response)
        except requests.exceptions.RequestException as e:
            on_failure(f"An error occurred during the request: {e}")
        finally:
            sleep(interval)


if __name__ == "__main__":
    check_api_status()
