---
name: hermes-performance-optimization
description: Systematic approach to identifying and fixing performance bottlenecks in Hermes Agent. Use when Hermes feels slow, startup is delayed, or memory usage is high.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, performance, optimization, profiling, caching]
    homepage: https://github.com/NousResearch/hermes-agent
    related_skills: [hermes-agent]
---

# Hermes Agent Performance Optimization

This skill provides a systematic approach to identifying and fixing performance bottlenecks in Hermes Agent. Use it when:
- Hermes startup is slow (>5 seconds)
- Memory usage is high (>500MB for idle agent)
- Tool response latency is noticeable (>2 seconds)
- Concurrent sessions degrade performance

## Quick Diagnostic Checklist

1. **Startup time**: Time from `hermes` command to first prompt
2. **Memory footprint**: Resident memory of Hermes process
3. **Tool initialization**: Time for tools to become available
4. **Session resume**: Time to load previous session context

## Common Performance Bottlenecks

### 1. Skills Loading Overhead
**Problem**: `_find_all_skills()` in `tools/skills_tool.py` recursively scans filesystem on every call.

**Solution**: Add caching:
```python
import functools

@functools.lru_cache(maxsize=1)
def get_cached_skills(skip_disabled=False):
    """Cached version of _find_all_skills."""
    return _find_all_skills(skip_disabled=skip_disabled)
```

**Impact**: 30-50% faster startup with many skills.

### 2. Tool Discovery Overhead
**Problem**: `discover_builtin_tools()` executes on each import despite singleton registry.

**Solution**: Cache discovery results:
```python
# In tools/registry.py
_TOOL_CACHE = {}

def get_cached_tools():
    if not _TOOL_CACHE:
        _TOOL_CACHE.update(discover_builtin_tools())
    return _TOOL_CACHE
```

### 3. Model Client Creation
**Problem**: New OpenAI clients created per session in `run_agent.py`.

**Solution**: Implement client pooling:
```python
from functools import lru_cache
from openai import OpenAI

@lru_cache(maxsize=10)
def get_cached_client(base_url, api_key, timeout):
    """Reuse clients with same parameters."""
    return OpenAI(base_url=base_url, api_key=api_key, timeout=timeout)
```

### 4. SQLite Connection Management
**Problem**: Global connection in `hermes_state.py` lacks pooling.

**Solution**: Add connection reuse with context managers:
```python
import sqlite3
from contextlib import contextmanager

_CONNECTION_POOL = {}

@contextmanager
def get_connection(db_path):
    conn = _CONNECTION_POOL.get(db_path)
    if not conn:
        conn = sqlite3.connect(db_path)
        _CONNECTION_POOL[db_path] = conn
    try:
        yield conn
    finally:
        # Keep connection open for reuse
        pass
```

### 5. Configuration Redundancy
**Problem**: Duplicate structures in `auxiliary` section and `platform_toolsets`.

**Solution**: Create shared configuration templates:
```yaml
# Instead of repeating for each auxiliary service
auxiliary:
  vision:
    provider: auto
    model: auto
  web_extract:
    provider: auto
    model: auto
  compression:
    provider: auto
    model: auto

# Use template
_auxiliary_template: &auxiliary_template
  provider: auto
  model: auto

auxiliary:
  vision: *auxiliary_template
  web_extract: *auxiliary_template
  compression: *auxiliary_template
```

## Optimization Priority Matrix

| Priority | Area | Action | Risk | Impact |
|----------|------|--------|------|--------|
| **High** | Skills caching | Add LRU cache | Low | 30-50% faster startup |
| **High** | Client pooling | Reuse OpenAI clients | Medium | Reduced connection overhead |
| **Medium** | SQLite pooling | Connection reuse | Low | Better concurrent performance |
| **Medium** | Tool discovery cache | Cache metadata | Low | Faster tool initialization |
| **Low** | Config templates | YAML anchors | Low | Smaller config, easier maintenance |
| **Low** | Scheduler evaluation | Consider alternatives | High | More precise scheduling |

## Step-by-Step Optimization Guide

### Phase 1: Quick Wins (Low Risk)
1. **Add skills caching**:
   - Locate `_find_all_skills()` in `tools/skills_tool.py`
   - Add `@functools.lru_cache(maxsize=1)` decorator
   - Test: `hermes --reset` should start faster

2. **Implement client pooling**:
   - Find client creation in `run_agent.py` (around line 4817)
   - Replace with cached client factory
   - Test: Multiple sessions should share connections

### Phase 2: Medium Improvements
3. **Cache tool discovery**:
   - Modify `discover_builtin_tools()` in `tools/registry.py`
   - Add memoization or disk cache
   - Test: Tool initialization time improves

4. **Pool SQLite connections**:
   - Update `hermes_state.py` connection handling
   - Use context managers for connection reuse
   - Test: Concurrent session performance

### Phase 3: Architectural Changes
5. **Evaluate scheduler**:
   - Assess `cron/scheduler.py` limitations
   - Consider `apscheduler` for large job counts
   - Test: Scheduling accuracy and resource usage

6. **Profile memory usage**:
   - Use `memory_profiler` to identify leaks
   - Check skill metadata duplication
   - Optimize large data structures

## Monitoring and Validation

### Before/After Metrics
```python
# Example benchmark script
import time
import subprocess

def benchmark_startup():
    start = time.time()
    subprocess.run(["hermes", "--version"], capture_output=True)
    return time.time() - start

def benchmark_skill_loading():
    # Measure time to load all skills
    pass
```

### Expected Improvements
- **Startup time**: 5s → 2-3s (with skills caching)
- **Memory usage**: 500MB → 300-400MB (after cleanup)
- **Tool latency**: 2s → <1s (with client pooling)
- **Concurrent sessions**: 5 → 10+ (with SQLite pooling)

## Risk Mitigation

1. **Cache invalidation**: Clear caches when files change (use file modification times)
2. **Backward compatibility**: Keep existing APIs unchanged
3. **Resource cleanup**: Ensure pools and caches have proper cleanup hooks
4. **Testing**: Add performance benchmarks to track improvements

## When Not to Optimize

- Single-user, low-usage scenarios
- Development environments where restart frequency is high
- When the bottleneck is external (network, API rate limits)
- If optimization complexity outweighs benefits

## Related Resources

- [Hermes Agent Documentation](https://hermes-agent.nousresearch.com/docs/)
- [Python Performance Profiling Guide](https://docs.python.org/3/library/profile.html)
- [SQLite Optimization Tips](https://www.sqlite.org/speed.html)

## Summary

Most Hermes Agent performance issues stem from:
1. **Uncached filesystem operations** (skills, tools)
2. **Resource creation overhead** (clients, connections)
3. **Configuration redundancy**

Start with skills caching and client pooling for immediate improvements. Monitor results before proceeding to more complex optimizations. Always measure before and after to validate impact.