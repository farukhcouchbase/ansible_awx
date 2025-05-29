
- name: Scan for vbucket corruption logs on Couchbase nodes
  hosts: all
  become: true
  vars:
    log_dir: "/opt/couchbase/var/lib/couchbase/logs"
    log_files_pattern: "memcached.log*"
    keywords: "vbucket.*malform"
  tasks:

    - name: Find matching log files
      find:
        paths: "{{ log_dir }}"
        patterns: "{{ log_files_pattern }}"
      register: log_files

    - name: Scan each log file for vbucket corruption
      block:
        - name: Grep log file for corruption patterns
          shell: |
            if [[ "{{ item.path }}" == *.gz ]]; then
              zgrep -iE "{{ keywords }}" "{{ item.path }}"
            else
              grep -iE "{{ keywords }}" "{{ item.path }}"
            fi
          args:
            executable: /bin/bash
          register: grep_results
          failed_when: false
          changed_when: false

        - name: Parse matched log lines
          when: grep_results.stdout != ""
          loop: "{{ grep_results.stdout_lines }}"
          loop_control:
            loop_var: log_line
          vars:
            vb_id: "{{ log_line | regex_search('vbucket[\\s#:-]*([0-9]+)', '\\1') }}"
            node_in_log: "{{ log_line | regex_search('node-[0-9a-zA-Z._-]+') }}"
          debug:
            msg: |
              ⚠️  Corruption Detected!
              Log File   : {{ item.path }}
              Node       : {{ node_in_log | default(inventory_hostname) }}
              Vbucket ID : {{ vb_id | default('Unknown') }}
              Log Line   : {{ log_line }}
      loop: "{{ log_files.files }}"
