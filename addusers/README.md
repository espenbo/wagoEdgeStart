# Add users from a CSV file

`addusersCSV.sh` creates the users listed in `users.csv`. It shows them in a table, including the passwords, and asks before it adds anything.

```sh
sudo ./addusersCSV.sh
```

Run it from this folder. Users that already exist are skipped.

## users.csv

The first line is the header. The file ends with a line that says `EOF`, and fields are separated by `;`:

```text
username;group0;group1;group2;group3;fullname;room;workphone;homephone;other;password
```

`users.csv` here only holds made-up example users. Keep your real list outside this repository, because it holds names, phone numbers and passwords.

## SSH access

If `/etc/ssh/sshd_config` has an `AllowUsers` line, the new users are added to it and SSH is restarted. Without such a line, every user can log in already and the file is left alone.
