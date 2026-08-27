import os
import time
from flask import Flask, request, jsonify, render_template
import psycopg2
import psycopg2.extras

app = Flask(__name__)

DB_HOST = os.environ.get("POSTGRES_HOST", "postgres-service")
DB_NAME = os.environ.get("POSTGRES_DB", "peopledb")
DB_USER = os.environ.get("POSTGRES_USER", "postgres")
DB_PASSWORD = os.environ.get("POSTGRES_PASSWORD", "postgres")

MAX_PEOPLE = 5


def get_connection():
    # Retry loop -- in k8s, the app pod can start before postgres is ready.
    retries = 10
    last_err = None
    for _ in range(retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
                connect_timeout=3,
            )
            return conn
        except psycopg2.OperationalError as e:
            last_err = e
            time.sleep(2)
    raise last_err


def init_db():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS people (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            age INTEGER NOT NULL,
            area VARCHAR(100) NOT NULL,
            created_at TIMESTAMP DEFAULT NOW()
        );
        """
    )
    conn.commit()
    cur.close()
    conn.close()

.
@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/api/people", methods=["GET"])
def get_people():
    conn = get_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT id, name, age, area FROM people ORDER BY id ASC;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(rows), 200


@app.route("/api/people", methods=["POST"])
def add_person():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    age = data.get("age")
    area = (data.get("area") or "").strip()

    if not name or not area or age is None:
        return jsonify({"error": "name, age, and area are all required"}), 400

    try:
        age = int(age)
    except (ValueError, TypeError):
        return jsonify({"error": "age must be a number"}), 400

    if age <= 0 or age > 130:
        return jsonify({"error": "enter a realistic age"}), 400

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM people;")
    count = cur.fetchone()[0]
    if count >= MAX_PEOPLE:
        cur.close()
        conn.close()
        return jsonify({"error": f"directory is full ({MAX_PEOPLE} people max)"}), 409

    cur.execute(
        "INSERT INTO people (name, age, area) VALUES (%s, %s, %s) RETURNING id;",
        (name, age, area),
    )
    new_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({"id": new_id, "name": name, "age": age, "area": area}), 201


@app.route("/api/people/<int:person_id>", methods=["DELETE"])
def delete_person(person_id):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DELETE FROM people WHERE id = %s;", (person_id,))
    deleted = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()

    if deleted == 0:
        return jsonify({"error": "person not found"}), 404
    return jsonify({"deleted": person_id}), 200


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
